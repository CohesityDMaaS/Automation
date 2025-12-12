[CmdletBinding(PositionalBinding=$False)]
param(
    [Parameter()][string]$vip = 'helios.cohesity.com',
    [Parameter()][string]$username = 'helios',
    [Parameter()][string]$password = $null,
    [Parameter()][string]$domain = 'local',
    [Parameter()][switch]$useApiKey,
    [Parameter()][switch]$mcm,
    [Parameter()][switch]$EntraId,
    [Parameter()][string]$clusterName = $null,

    # Wait/progress behavior
    
	#[Parameter()][switch]$wait,
    #[Parameter()][switch]$progress,

    # Tuning
    [Parameter()][int]$timeoutSec = 300,
    [Parameter()][int]$statusRetries = 10,
    [Parameter()][int]$sleepTimeSecs = 60,
    [Parameter()][int]$waitForNewRunMinutes = 50,
    [Parameter()][int]$startWaitTime = 30,
    [Parameter()][int]$retryWaitTime = 60,
    [Parameter()][switch]$noCache,

    # Job filters
    [Parameter()][string]$JobName,     # run for a single job
    [Parameter()][string]$JobList,     # path to txt file with job names

    # Behavior controls
    [Parameter()][switch]$DryRun,      # show expiration, do not start jobs
    [Parameter()][switch]$Commit,      # actually start jobs

    # Logging controls
    [Parameter()][switch]$WriteLog,    # enable console output to file
    [Parameter()][string]$LogPath = $null,  # optional custom log path

    # NEW: Months to keep replica for
    [Parameter()][int]$keepReplicaForMonths = 4
)

# -------------------------------------------------------------------------
# WriteLog: capture all console output to a file via transcript
# -------------------------------------------------------------------------
$script:TranscriptStarted = $false

function Stop-Log {
    if ($script:TranscriptStarted) {
        try { 
            Stop-Transcript | Out-Null 
        } catch {
            # Silently ignore if transcript wasn't started
        }
        $script:TranscriptStarted = $false
    }
}

if ($WriteLog) {
    $logFile = if ([string]::IsNullOrWhiteSpace($LogPath)) {
        Join-Path $PSScriptRoot ("cohesity_runlog_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    } else {
        $LogPath
    }

    try {
        Start-Transcript -Path $logFile -Append -ErrorAction Stop | Out-Null
        $script:TranscriptStarted = $true
        Write-Host ("WriteLog enabled: capturing console output to {0}" -f $logFile) -ForegroundColor Cyan
    } catch {
        Write-Host ("WARNING: Could not start transcript: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        $WriteLog = $false
    }
}

# -------------------------------------------------------------------------
# Validate DryRun/Commit usage
# -------------------------------------------------------------------------
if ($DryRun -and $Commit) {
    Write-Host "You cannot specify both -DryRun and -Commit." -ForegroundColor Yellow
    Stop-Log
    exit 1
}

if (-not $DryRun -and -not $Commit) {
    Write-Host "INFO: Neither -DryRun nor -Commit specified. Defaulting to DryRun behavior (no jobs will be started)." -ForegroundColor Yellow
    $DryRun = $true
}

# cache setting used in URL
$cacheSetting = if ($noCache) { 'false' } else { 'true' }

# Require cohesity-api.ps1 in same folder
. $(Join-Path -Path $PSScriptRoot -ChildPath 'cohesity-api.ps1')

# Auth
apiauth -vip $vip -username $username -domain $domain -passwd $password `
        -apiKeyAuthentication $useApiKey -heliosAuthentication $mcm -entraIdAuthentication $EntraId

if ($USING_HELIOS -and $clusterName) {
    $null = heliosCluster $clusterName
}

if (-not $cohesity_api.authorized) {
    Write-Host "Not authenticated" -ForegroundColor Yellow
    Stop-Log
    exit 2
}

# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------
function Get-DaysToEndOfMonthPlusMonthsUtc {
    param([int]$monthsAhead)

    # Work in LOCAL time and floor to the last calendar day of the target month
    $nowLocal  = Get-Date
    $target    = $nowLocal.AddMonths($monthsAhead)
    $lastDay   = [DateTime]::DaysInMonth($target.Year, $target.Month)
    $eomLocalD = Get-Date -Year $target.Year -Month $target.Month -Day $lastDay

    # Whole calendar days between today's date and EOM date (floor)
    $days = [int]($eomLocalD.Date - $nowLocal.Date).TotalDays

    # Safety clamp
    if ($days -lt 1) { $days = 1 }

    Write-Host ("Today (local):      {0}" -f $nowLocal.ToString('yyyy-MM-dd'))
    Write-Host ("Target EOM (local): {0}" -f $eomLocalD.ToString('yyyy-MM-dd'))
    Write-Host ("daysToEOM (floor):  {0}" -f $days)
    return $days
}
# Use the new parameter here instead of hard-coded 4
$keepReplicaForDays = Get-DaysToEndOfMonthPlusMonthsUtc -monthsAhead $keepReplicaForMonths


# Finished states (both numeric and named)
$finishedStates = @(
    'kCanceled','kSuccess','kFailure','kWarning',
    '3','4','5','6',
    'Canceled','Succeeded','Failed','SucceededWithWarning'
)

# -------------------------------------------------------------------------
# Fetch all active protection groups (v2)
# -------------------------------------------------------------------------
$jobs = api get -v2 "data-protect/protection-groups?isActive=true&isDeleted=false&pruneSourceIds=true&pruneExcludedSourceIds=true&useCachedData=$cacheSetting" -timeout $timeoutSec
$allActiveJobs = @($jobs.protectionGroups)
if ($allActiveJobs.Count -eq 0) {
    Write-Host "No active protection groups found." -ForegroundColor Yellow
    Stop-Log
    exit 0
}
Write-Host ("Found {0} active protection groups" -f $allActiveJobs.Count)

# -------------------------------------------------------------------------
# Build requested job set from -JobName / -JobList
# -------------------------------------------------------------------------
$jobNamesFromFile = @()
if ($JobList) {
    if (Test-Path $JobList) {
        $jobNamesFromFile = Get-Content -Path $JobList | Where-Object { $_.Trim() -ne "" }
    } else {
        Write-Host ("JobList file not found: {0}" -f $JobList) -ForegroundColor Yellow
        Stop-Log
        exit 1
    }
}

$requestedJobNames = @()
if ($JobName)          { $requestedJobNames += $JobName }
if ($jobNamesFromFile) { $requestedJobNames += $jobNamesFromFile }

$requestedJobNames = $requestedJobNames |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne "" } |
    Sort-Object -Unique

if ($requestedJobNames.Count -eq 0) {
    # No filters: process all active jobs (existing behavior)
    $jobsToProcess = $allActiveJobs
    Write-Host "No JobName/JobList specified. Processing ALL active jobs."
} else {
    # Filter to only requested job names (exact match)
    $jobsToProcess = $allActiveJobs | Where-Object {
        $requestedJobNames -contains $_.name
    }

    # Warn about any requested names that don't match an active job
    $notFound = $requestedJobNames | Where-Object {
        -not ($allActiveJobs.name -contains $_)
    }
    if ($notFound.Count -gt 0) {
        Write-Host ("The following requested jobs were not found or not active: {0}" -f ($notFound -join ', ')) -ForegroundColor Yellow
    }

    if ($jobsToProcess.Count -eq 0) {
        Write-Host "No matching active jobs to process. Exiting." -ForegroundColor Yellow
        Stop-Log
        exit 1
    }

    Write-Host ("Will process {0} job(s): {1}" -f $jobsToProcess.Count, ($jobsToProcess.name -join ', '))
}

# -------------------------------------------------------------------------
# Main loop over selected jobs
# -------------------------------------------------------------------------
foreach ($job in $jobsToProcess) {

    $jobName = $job.name
    $v2JobId = $job.id
    $v1JobId = ($v2JobId -split ":")[-1]
    $policyId = $job.policyId

    Write-Host ""
    Write-Host ("=== Processing: {0} ===" -f $jobName)

    # ---------------------------------------------------------------------
    # Build copyRunTargets from policy, override daysToKeep for replication
    # ---------------------------------------------------------------------
    $copyRunTargets = @()
    $addedTargets = @{}  # use a hashtable keyed by a unique ID
    $policy = api get "protectionPolicies/$policyId" -timeout $timeoutSec

    if ($policy.PSObject.Properties['snapshotReplicationCopyPolicies']) {

        foreach ($rep in $policy.snapshotReplicationCopyPolicies) {

            # Choose a stable unique key for the target
            $targetId = $null

            if ($rep.target.PSObject.Properties['clusterId']) {
                $targetId = "clusterId:{0}" -f $rep.target.clusterId
            }
            elseif ($rep.target.PSObject.Properties['clusterName']) {
                $targetId = "clusterName:{0}" -f $rep.target.clusterName
            }
            else {
                # Last resort: serialize; slower but safe
                $targetId = ($rep.target | ConvertTo-Json -Depth 10)
            }

            # Skip if we've already added this target
            if ($addedTargets.ContainsKey($targetId)) {
                continue
            }

            $copyRunTargets += @{
                type              = "kRemote"
                daysToKeep        = $keepReplicaForDays
                replicationTarget = $rep.target
            }

            $addedTargets[$targetId] = $true
        }

    } else {
        Write-Host ("No replication policies found in policy for {0}; will not add remote copy target." -f $jobName) -ForegroundColor Yellow
    }

    # ---------------------------------------------------------------------
    # DryRun/Commit: report calculated expiration date(s) for replication
    # ---------------------------------------------------------------------
    if ($copyRunTargets.Count -gt 0) {
        $today      = (Get-Date).Date

        # Recompute the same Target EOM that Get-DaysToEndOfMonthPlusMonths uses
        $monthsAhead = $keepReplicaForMonths   # <-- driven by parameter
        $target      = $today.AddMonths($monthsAhead)
        $lastDay     = [DateTime]::DaysInMonth($target.Year, $target.Month)
        $eomDate     = Get-Date -Year $target.Year -Month $target.Month -Day $lastDay

        # daysToKeep is already calculated from today → EOM
        $expireDate = $eomDate

        Write-Host ("If a replication run starts today ({0}), expiration (Target EOM) would be: {1}" -f `
            $today.ToString('yyyy-MM-dd'),
            $expireDate.ToString('yyyy-MM-dd'))

        foreach ($t in $copyRunTargets) {
            $tgt = $t.replicationTarget
            $tName = $null
            if ($tgt.PSObject.Properties['clusterName']) {
                $tName = $tgt.clusterName
            }
            elseif ($tgt.PSObject.Properties['clusterId']) {
                $tName = ("clusterId:{0}" -f $tgt.clusterId)
            }
            else {
                $tName = "<unknown target>"
            }

            Write-Host ("  Target: {0} -> expiration (Target EOM): {1}" -f `
                $tName,
                $expireDate.ToString('yyyy-MM-dd'))
        }
    } else {
        Write-Host ("Job {0} has no replication targets; nothing to report for retention/expiration." -f $jobName) -ForegroundColor Yellow
    }

    # ---------------------------------------------------------------------
    # Start run (only if Commit)
    # ---------------------------------------------------------------------
    $jobdata = @{
        runType           = 'kRegular'
        usePolicyDefaults = $false   # we're overriding replica retention
        copyRunTargets    = $copyRunTargets
    }

    if ($DryRun) {
        Write-Host ("DryRun: NOT starting job {0}. Use -Commit to actually run with these settings." -f $jobName) -ForegroundColor Yellow
        # skip wait/progress for DryRun
        continue
    }

    # Only executed if Commit is true
    $result = api post ("protectionJobs/run/$v1JobId") $jobdata -timeout $timeoutSec -quiet
    if ($result -eq "") {
        Write-Host ("Started: {0}" -f $jobName)
    } else {
        $err = $cohesity_api.last_api_error
        if ($err -match "outstanding run-now request|already has a run|existing active backup run|only have one active backup run") {
            Write-Host ("Job already running: {0}" -f $jobName)
        } else {
            Write-Host ("Start error: {0}" -f $err) -ForegroundColor Yellow
            continue
        }
    }

    if (-not ($wait -or $progress)) {
        # user does not want to wait/track progress
        continue
    }

    # ---------------------------------------------------------------------
    # Baseline last run info
    # ---------------------------------------------------------------------
    $runs = api get -v2 "data-protect/protection-groups/$v2JobId/runs?numRuns=1&includeObjectDetails=false&useCachedData=$cacheSetting" -timeout $timeoutSec

    if ($null -ne $runs -and $runs.PSObject.Properties['runs']) {
        $runs = @($runs.runs)
    } else {
        $runs = @()
    }

    # defaults if no previous runs
    $lastRunId    = 1
    $newRunId     = 1
    $lastRunUsecs = 1662164882000000  # some old timestamp as baseline

    if ($runs -and $runs.Count -gt 0) {
        $lastRunId = $runs[0].protectionGroupInstanceId

        if ($runs[0].PSObject.Properties['localBackupInfo']) {
            $lastRunUsecs = $runs[0].localBackupInfo.startTimeUsecs
        } elseif ($runs[0].PSObject.Properties['archivalInfo'] -and
                  $runs[0].PSObject.Properties['archivalInfo'].archivalTargetResults -and
                  $runs[0].archivalInfo.archivalTargetResults.Count -gt 0) {
            $lastRunUsecs = $runs[0].archivalInfo.archivalTargetResults[0].startTimeUsecs
        }
    }

    # ---------------------------------------------------------------------
    # Wait for new run to appear
    # ---------------------------------------------------------------------
    $newRunId = $lastRunId
    $v2RunId  = $null
    $deadline = (Get-Date).AddMinutes($waitForNewRunMinutes)

    while ($newRunId -le $lastRunId) {
       if ((Get-Date) -gt $deadline) {
            Write-Host "Timed out waiting for new run to appear" -ForegroundColor Yellow
            break
        }

        Start-Sleep -Seconds $startWaitTime

        $runs = api get -v2 "data-protect/protection-groups/$v2JobId/runs?numRuns=3&includeObjectDetails=false&useCachedData=$cacheSetting&startTimeUsecs=$lastRunUsecs" -timeout $timeoutSec
        if ($null -ne $runs -and $runs.PSObject.Properties['runs']) {
            $runs = @($runs.runs)
        } else {
            $runs = @()
        }

        # filter runs newer than the last one we saw
        $runs = @($runs | Where-Object { $_.protectionGroupInstanceId -gt $lastRunId })
        if ($runs.Count -gt 0) {
            $newRunId = $runs[0].protectionGroupInstanceId
            $v2RunId  = $runs[0].id
            break
        }
    }

    if ($newRunId -le $lastRunId) {
        Write-Host ("Skipping wait - no new run detected for {0}" -f $jobName) -ForegroundColor Yellow
        continue
    }

    Write-Host ("New run: {0}" -f $v2RunId)

    # ---------------------------------------------------------------------
    # Progress/status loop
    # ---------------------------------------------------------------------
    $statusRetryCount = 0
    $lastStatus       = 'unknown'
    $lastProgressPct  = -1
    $backupInfo       = $null

    while ($lastStatus -notin $finishedStates) {
        Start-Sleep -Seconds $sleepTimeSecs
        $bump = $true
        try {
            $run = api get -v2 "data-protect/protection-groups/$v2JobId/runs/$v2RunId?includeObjectDetails=false&useCachedData=$cacheSetting" -timeout $timeoutSec
            if ($run) {
                if ($run.PSObject.Properties['localBackupInfo']) {
                    $backupInfo = $run.localBackupInfo
                } elseif ($run.PSObject.Properties['archivalInfo'] -and $run.archivalInfo.archivalTargetResults) {
                    $backupInfo = $run.archivalInfo.archivalTargetResults[0]
                } else {
                    $backupInfo = $null
                }

                if ($backupInfo -and $backupInfo.PSObject.Properties['status']) {
                    $lastStatus = $backupInfo.status
                    $bump = $false
                }

                if ($progress -and $backupInfo -and $backupInfo.PSObject.Properties['progressTaskId']) {
                    try {
                        $progressPath = $backupInfo.progressTaskId
                        $pm = api get "/progressMonitors?taskPathVec=$progressPath&excludeSubTasks=true&includeFinishedTasks=false&useCachedData=$cacheSetting" -timeout $timeoutSec
                        if ($pm -and $pm.PSObject.Properties['resultGroupVec'] -and $pm.resultGroupVec.Count -gt 0) {
                            $firstGroup = $pm.resultGroupVec[0]
                            if ($firstGroup.taskVec -and $firstGroup.taskVec.Count -gt 0) {
                                $pct = $firstGroup.taskVec[0].progress.percentFinished
                                $pct = [math]::Round($pct,0)
                                if ($pct -ne $lastProgressPct) {
                                    Write-Host ("{0} percent complete" -f $pct)
                                    $lastProgressPct = $pct
                                }
                            }
                        }
                    } catch {
                        # ignore progress-monitor errors
                    }
                }
            }
        } catch {
            $bump = $true
        }

        if ($bump) {
            $statusRetryCount++
        } else {
            $statusRetryCount = 0
        }

        if ($statusRetryCount -gt $statusRetries) {
            Write-Host "Timed out waiting for status update" -ForegroundColor Yellow
            break
        }
    }

    # ---------------------------------------------------------------------
    # Normalize and report final status
    # ---------------------------------------------------------------------
    $statusMap = @('0','1','2','Canceled','Succeeded','Failed','SucceededWithWarning')
    if ($backupInfo -and $backupInfo.status -in @('3','4','5','6')) {
        $backupInfo.status = $statusMap[[int]$backupInfo.status]
    }

    if ($backupInfo) {
        Write-Host ("Job finished with status: {0}" -f $backupInfo.status)
        if ($backupInfo.status -eq 'Succeeded') {
            Write-Host ("OK {0} completed successfully" -f $jobName)
        } elseif ($backupInfo.status -eq 'SucceededWithWarning') {
            if ($backupInfo.PSObject.Properties['messages'] -and $backupInfo.messages.Count -gt 0) {
                Write-Host ("Warning: {0}" -f ($backupInfo.messages -join '; '))
            }
            Write-Host ("WARN {0} completed with warnings" -f $jobName)
        } elseif ($backupInfo.status -eq 'Failed') {
            if ($backupInfo.PSObject.Properties['messages'] -and $backupInfo.messages.Count -gt 0) {
                Write-Host ("Error: {0}" -f ($backupInfo.messages -join '; ')) -ForegroundColor Yellow
            }
            Write-Host ("FAIL {0} failed" -f $jobName) -ForegroundColor Yellow
        }
    } else {
        Write-Host "Could not retrieve final job status" -ForegroundColor Yellow
    }
}  # end foreach jobsToProcess

Write-Host ""
Write-Host "All requested jobs processed."

# -------------------------------------------------------------------------
# Stop transcript if it was started
# -------------------------------------------------------------------------
Stop-Log

