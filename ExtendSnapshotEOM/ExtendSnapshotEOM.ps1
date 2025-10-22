# Enable advanced functions features like CmdletBinding and parameter validation
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip,
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$domain = 'local',
    [Parameter()][array]$jobName,
    [Parameter()][string]$jobList = '',
    [Parameter()][array]$policyName,
    [Parameter()][string]$policyList,
    [Parameter()][switch]$includeReplicas,
    [Parameter()][switch]$commit,
    [Parameter(Mandatory = $True)][int]$extendMonths,
    [Parameter()][switch]$IncludeSnapshotDay,
    [Parameter()][string]$LogPath,
    [Parameter()][switch]$DryRun,
    [Parameter()][switch]$DebugLog,
    [Parameter()][int]$MaxLogs = 10,
    [Parameter()][switch]$ArchiveOldLogs,
    [Parameter()][DateTime]$SnapshotDate
)

# -------------------------------------------------------------
# Validate DryRun / Commit
# -------------------------------------------------------------
if (-not $DryRun -and -not $commit) {
    Write-Error "You must specify either -DryRun or -Commit. Exiting."
    exit
}

# -------------------------------------------------------------
# Prepare log file
# -------------------------------------------------------------
if (-not $LogPath -or $LogPath -eq '') {
    $timestamp = (Get-Date -Format "yyyy-MM-dd_HHmm")
    $LogPath = "extendLog_$timestamp.txt"
}
$logFullPath = Join-Path -Path $PWD -ChildPath $LogPath
if (-not (Test-Path $logFullPath)) { "" | Out-File -FilePath $logFullPath -Encoding UTF8 }

# -------------------------------------------------------------
# Logging helpers
# -------------------------------------------------------------
function Write-DebugLog($msg) { if ($DebugLog) { $line = "[DEBUG] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $msg"; Write-Host $line -ForegroundColor Gray; $line | Out-File -FilePath $logFullPath -Append } }
function Write-InfoLog($msg) { $line = "[INFO] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $msg"; Write-Host $line -ForegroundColor White; $line | Out-File -FilePath $logFullPath -Append }
function Write-ErrorLog($msg, $ex=$null) { $line = "[ERROR] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $msg"; Write-Host $line -ForegroundColor Red; $line | Out-File -FilePath $logFullPath -Append; if ($ex) { $ex.Exception.Message | Out-File -FilePath $logFullPath -Append } }

# -------------------------------------------------------------
# Log rotation
# -------------------------------------------------------------
$logPattern = "extendLog_*.txt"
$logDir = Split-Path -Parent $logFullPath
$logFiles = Get-ChildItem -Path $logDir -Filter $logPattern | Sort-Object LastWriteTime -Descending
if ($logFiles.Count -gt $MaxLogs) {
    $logsToRemove = $logFiles[$MaxLogs..($logFiles.Count - 1)]
    if ($ArchiveOldLogs) {
        $archiveName = "archivedLogs_{0}.zip" -f (Get-Date -Format "yyyyMMdd_HHmmss")
        $archivePath = Join-Path -Path $logDir -ChildPath $archiveName
        Write-InfoLog "Archiving old logs to: $archivePath"
        try { Compress-Archive -Path $logsToRemove.FullName -DestinationPath $archivePath -Force; $logsToRemove | ForEach-Object { Remove-Item $_.FullName -Force } } catch { Write-ErrorLog "Failed to archive old logs" $_ }
    } else {
        $logsToRemove | ForEach-Object { try { Remove-Item $_.FullName -Force } catch { Write-ErrorLog "Failed to delete old log: $($_.FullName)" $_ } }
    }
}
Write-DebugLog "Log rotation complete. Active logs retained: $MaxLogs"

# -------------------------------------------------------------
# Gather jobs and policies
# -------------------------------------------------------------
$jobsToUpdate = @()
foreach ($job in $jobName) { $jobsToUpdate += $job }
if ($jobList -and (Test-Path $jobList)) { $jobsToUpdate += Get-Content $jobList | ForEach-Object { $_.Trim() } }

$policiesToUpdate = @()
foreach ($policy in $policyName) { $policiesToUpdate += $policy }
if ($policyList -and (Test-Path $policyList)) { $policiesToUpdate += Get-Content $policyList | ForEach-Object { $_.Trim() } }

Write-DebugLog "Jobs to update: $($jobsToUpdate -join ', ')"
Write-DebugLog "Policies to update: $($policiesToUpdate -join ', ')"

# -------------------------------------------------------------
# Load Cohesity API and authenticate
# -------------------------------------------------------------
. $(Join-Path -Path $PSScriptRoot -ChildPath "cohesity-api.ps1")
apiauth -vip $vip -username $username -domain $domain
Write-DebugLog "Authenticated with Cohesity cluster $vip"

# -------------------------------------------------------------
# Retrieve jobs
# -------------------------------------------------------------
$allJobs = (api get -v2 data-protect/protection-groups).protectionGroups | Where-Object { $_.isDeleted -ne $true }

if ($jobsToUpdate.Count -gt 0) { $allJobs = $allJobs | Where-Object { $_.name -in $jobsToUpdate } }
if ($policiesToUpdate.Count -gt 0) {
    $policies = (api get -v2 data-protect/policies).policies | Where-Object { $_.name -in $policiesToUpdate }
    $policyIds = $policies.id
    $allJobs = $allJobs | Where-Object { $_.policyId -in $policyIds }
}

# Filter replicas if requested
if (-not $includeReplicas) {
    $jobs = $allJobs | Where-Object { $_.isReplicationJob -ne $true }
    Write-DebugLog "Replicas excluded from job list"
} else {
    $jobs = $allJobs
    Write-DebugLog "Including replica jobs"
}

# -------------------------------------------------------------
# Determine snapshot date
# -------------------------------------------------------------
if ($SnapshotDate) { $snapshotDay = Get-Date $SnapshotDate; Write-DebugLog "Using user-specified snapshot date: $snapshotDay" }
else { $snapshotDay = (Get-Date -Year (Get-Date).Year -Month (Get-Date).Month -Day 1).AddDays(-1); Write-DebugLog "Using last day of previous month as snapshot: $snapshotDay" }

# -------------------------------------------------------------
# Process each job and calculate new retention
# -------------------------------------------------------------
$results = @()
$usecsPerDay = 86400000000

foreach ($job in $jobs | Sort-Object -Property name) {
    Write-DebugLog "Processing job $($job.name)"

    # Retrieve runs around snapshot date
    $startTimeUsecs = [int64]((Get-Date $snapshotDay.AddDays(-1) -Hour 0 -Minute 0 -Second 0).ToUniversalTime() - [datetime]'1970-01-01').TotalMilliseconds * 1000
    $endTimeUsecs   = [int64]((Get-Date $snapshotDay.AddDays(1) -Hour 23 -Minute 59 -Second 59).ToUniversalTime() - [datetime]'1970-01-01').TotalMilliseconds * 1000

    $runs = (api get -v2 "data-protect/protection-groups/$($job.id)/runs?startTimeUsecs=$startTimeUsecs&endTimeUsecs=$endTimeUsecs&numRuns=9999&includeObjectDetails=false&runTypes=kSystem,kIncremental,kFull").runs
    Write-DebugLog "Retrieved $($runs.Count) runs for $($job.name)"

    # Corrected run selection to include replicas
    $latestRun = $runs | Where-Object {
        $runUsecs = if ($_.isReplicationRun) { $_.originalBackupInfo.startTimeUsecs } else { $_.localBackupInfo.startTimeUsecs }
        $runDate = (usecsToDate $runUsecs).Date
        $replicaOk = $includeReplicas -or (-not $_.isReplicationRun)
        $dateOk = $runDate -eq $snapshotDay.Date
        $replicaOk -and $dateOk
    } | Sort-Object { if ($_.isReplicationRun) { $_.originalBackupInfo.startTimeUsecs } else { $_.localBackupInfo.startTimeUsecs } } -Descending | Select-Object -First 1

    if (-not $latestRun) { Write-DebugLog "No applicable run found for $($job.name) on $snapshotDay"; continue }

    # Calculate new expiry
    $runStartUsecs = if ($latestRun.isReplicationRun) { $latestRun.originalBackupInfo.startTimeUsecs } else { $latestRun.localBackupInfo.startTimeUsecs }
    $thisRun = api get "/backupjobruns?allUnderHierarchy=true&exactMatchStartTimeUsecs=$runStartUsecs&excludeTasks=true&id=$($job.id.split(':')[-1])"
    $currentExpireUsecs = ($thisRun.backupJobRuns.protectionRuns[0].copyRun.finishedTasks | Where-Object {$_.snapshotTarget.type -eq 1}).expiryTimeUsecs

    $lastDayExtendedMonth = $snapshotDay.AddMonths($extendMonths)
    $lastDayExtendedMonth = Get-Date -Year $lastDayExtendedMonth.Year -Month $lastDayExtendedMonth.Month -Day ([DateTime]::DaysInMonth($lastDayExtendedMonth.Year, $lastDayExtendedMonth.Month))

    $daysToKeep = if ($IncludeSnapshotDay) { ($lastDayExtendedMonth - $snapshotDay).Days + 1 } else { ($lastDayExtendedMonth - $snapshotDay).Days }
    $newExpireUsecs = $runStartUsecs + ($daysToKeep * $usecsPerDay)
    $daysToExtend = [int][math]::Round(($newExpireUsecs - $currentExpireUsecs)/$usecsPerDay)

    $results += [pscustomobject]@{
        JobName           = $job.name
        SnapshotDate      = (usecsToDate $runStartUsecs).ToString('yyyy-MM-dd')
        CurrentExpiryDate = (usecsToDate $currentExpireUsecs).ToString('yyyy-MM-dd')
        NewExpiryDate     = (usecsToDate $newExpireUsecs).ToString('yyyy-MM-dd')
        DaysExtended      = $daysToExtend
    }

    # Commit changes if requested
    if ($commit -and $daysToExtend -gt 0) {
        $runParams = @{
            jobRuns = @(@{
                jobUid = @{
                    clusterId = $thisRun.backupJobRuns.protectionRuns[0].copyRun.jobUid.clusterId
                    clusterIncarnationId = $thisRun.backupJobRuns.protectionRuns[0].copyRun.jobUid.clusterIncarnationId
                    id = $thisRun.backupJobRuns.protectionRuns[0].copyRun.jobUid.objectId
                }
                runStartTimeUsecs = $runStartUsecs
                copyRunTargets = @(@{ type="kLocal"; daysToKeep=[int]$daysToExtend })
            })
        }
        try { $null = api put protectionRuns $runParams; Write-DebugLog "Retention updated for $($job.name)" } catch { Write-ErrorLog "Failed to update retention for $($job.name)" $_ }
    }
}

# -------------------------------------------------------------
# Output summary table (aligned)
# -------------------------------------------------------------
if ($results.Count -gt 0) {
    $colFormat = "{0,-35} {1,-12} {2,-12} {3,-12} {4,5}"
    Write-Host "`n✅ Retention Extension Summary" -ForegroundColor Cyan
    Write-Host "---------------------------------------------------------------------"
    Write-Host ($colFormat -f "Job Name","Snapshot","Current Exp","New Exp","Days")
    Write-Host ($colFormat -f "--------","--------","-----------","-------","----")
    foreach ($row in $results | Sort-Object JobName) {
        $color = if ($row.DaysExtended -gt 0) { 'Green' } else { 'Yellow' }
        Write-Host ($colFormat -f $row.JobName,$row.SnapshotDate,$row.CurrentExpiryDate,$row.NewExpiryDate,$row.DaysExtended) -ForegroundColor $color
    }
    Write-Host "---------------------------------------------------------------------"
    Write-Host ("Total Jobs: {0}, Extended: {1}, Total Days Extended: {2}" -f $results.Count, ($results | Where-Object { $_.DaysExtended -gt 0 }).Count, ($results | Measure-Object DaysExtended -Sum).Sum) -ForegroundColor Cyan
} else { Write-Warning "No applicable snapshots found for retention extension." }
