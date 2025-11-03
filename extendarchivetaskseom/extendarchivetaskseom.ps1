<#
.SYNOPSIS
Extends retention for archived snapshots to end of extended month. 
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip,
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$domain = 'local',
    [Parameter(Mandatory = $False)][int]$extendMonths,
    [Parameter(Mandatory = $False)][int]$daysToKeep,
    [Parameter(Mandatory = $False)][datetime]$snapshotDate,
    [Parameter(Mandatory = $False)][datetime]$StartDate,
    [Parameter(Mandatory = $False)][datetime]$EndDate,
    [Parameter(Mandatory = $False)][switch]$includeSnapshotDay,
    [Parameter()][string]$password,
    [Parameter()][switch]$noPrompt,
    [Parameter()][array]$jobNames,
    [Parameter()][array]$policyNames,
    [Parameter()][string]$jobList,
    [Parameter()][string]$policyList,
    [Parameter()][string]$target,
    [Parameter()][switch]$allowReduction,
    [Parameter()][switch]$commit,
    [Parameter()][switch]$DryRun,
    [Parameter()][string]$SummaryCsv,
    [Parameter()][switch]$lastSnapshotOfPreviousMonth,
    [Parameter()][switch]$lastSnapshotOfCurrentMonth,
    [Parameter()][switch]$DebugLog
)

function Write-DebugLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    if ($DebugLog) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp][$Level] $Message"
    }
}

function Read-ListFromFile {
    param(
        [string]$FilePath,
        [string]$ListType
    )
    
    if ([string]::IsNullOrWhiteSpace($FilePath)) {
        return $null
    }
    
    if (-not (Test-Path $FilePath)) {
        Write-Host "ERROR: $ListType file not found: $FilePath" -ForegroundColor Red
        Write-DebugLog "$ListType file not found: $FilePath" "ERROR"
        exit 1
    }
    
    try {
        $items = Get-Content -Path $FilePath | Where-Object { $_.Trim() -ne "" -and $_ -notmatch "^\s*#" }
        Write-DebugLog "Loaded $($items.Count) items from $ListType file: $FilePath"
        Write-Host "Loaded $($items.Count) $ListType from file: $FilePath" -ForegroundColor Cyan
        return $items
    }
    catch {
        Write-Host "ERROR: Failed to read $ListType file: $FilePath - $_" -ForegroundColor Red
        Write-DebugLog "Failed to read $ListType file: $FilePath - $_" "ERROR"
        exit 1
    }
}

if ($jobList) {
    $fileJobNames = Read-ListFromFile -FilePath $jobList -ListType "job names"
    if ($fileJobNames) {
        if ($jobNames) {
            $jobNames = $jobNames + $fileJobNames | Select-Object -Unique
            Write-DebugLog "Merged job names from file with parameter array"
        } else {
            $jobNames = $fileJobNames
        }
    }
}

if ($policyList) {
    $filePolicyNames = Read-ListFromFile -FilePath $policyList -ListType "policy names"
    if ($filePolicyNames) {
        if ($policyNames) {
            $policyNames = $policyNames + $filePolicyNames | Select-Object -Unique
            Write-DebugLog "Merged policy names from file with parameter array"
        } else {
            $policyNames = $filePolicyNames
        }
    }
}

if ($jobNames) {
    Write-Host "Filtering by jobs: $($jobNames -join ', ')" -ForegroundColor Cyan
    Write-DebugLog "Job filter active: $($jobNames -join ', ')"
}
if ($policyNames) {
    Write-Host "Filtering by policies: $($policyNames -join ', ')" -ForegroundColor Cyan
    Write-DebugLog "Policy filter active: $($policyNames -join ', ')"
}

if (-not ($lastSnapshotOfPreviousMonth -or $lastSnapshotOfCurrentMonth) -and
    (($PSBoundParameters.ContainsKey('daysToKeep') -and $PSBoundParameters.ContainsKey('extendMonths')) -or
     (-not $PSBoundParameters.ContainsKey('daysToKeep') -and -not $PSBoundParameters.ContainsKey('extendMonths')))) {
    Write-Host "ERROR: You must specify exactly ONE of -daysToKeep or -extendMonths." -ForegroundColor Red
    exit 1
}

. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)
Write-DebugLog "Loaded cohesity-api.ps1"

Write-Host "Connecting to Cohesity cluster $vip..."
Write-DebugLog "Attempting API auth with user $username@$domain"
apiauth -vip $vip -username $username -domain $domain -passwd $password -noPromptForPassword $noPrompt
if (!$cohesity_api.authorized) {
    Write-DebugLog "Authentication failed for $username@$vip" "ERROR"
    Write-Host "Not authenticated" -ForegroundColor Yellow
    exit 1
}
Write-DebugLog "Authentication succeeded"
Write-Host "Connected to $vip successfully." -ForegroundColor Green
Write-Host ""

Write-DebugLog "Fetching protection policies..."
$policies = api get protectionPolicies
Write-DebugLog ("Found {0} policies" -f $policies.Count)

Write-DebugLog "Fetching protection jobs..."
$jobs = api get protectionJobs
Write-DebugLog ("Found {0} jobs" -f $jobs.Count)

$summary = @()
$usecsPerDay = 86400000000

foreach ($job in $jobs | Sort-Object -Property name) {
    Write-DebugLog "Processing job: $($job.name)"
    $policy = $policies | Where-Object { $_.id -eq $job.policyId }
    if ($policy) {
        Write-DebugLog "Matched policy: $($policy.name)"
    } else {
        Write-DebugLog "No matching policy found for job $($job.name)" "WARN"
    }

    if (!$policyNames -or ($policy -and $policy.name -in $policyNames)) {
        $jobName = $job.name
        if (!$jobNames -or $job.name -in $jobNames) {
            Write-Host "$jobName"
            Write-DebugLog "Fetching archival runs for job $jobName..."
            
            $apiUrl = "protectionRuns?jobId=$($job.id)&excludeTasks=true&excludeNonRestoreableRuns=true&numRuns=999999&runTypes=kRegular"
            $allRuns = api get $apiUrl
            $runs = $allRuns | Where-Object { 'kArchival' -in $_.copyRun.target.type }
            
            # Sort runs by first copyRun's runStartTimeUsecs
            $sortedRuns = @()
            foreach ($r in $runs) {
                $firstCopyRun = $r.copyRun | Select-Object -First 1
                $sortedRuns += [PSCustomObject]@{
                    Run = $r
                    SortKey = $firstCopyRun.runStartTimeUsecs
                }
            }
            $runs = $sortedRuns | Sort-Object -Property SortKey | ForEach-Object { $_.Run }
            
            Write-DebugLog ("Found {0} archival runs" -f $runs.Count)

            if ($snapshotDate) {
                Write-DebugLog "Filtering runs for snapshot date $($snapshotDate.ToString('yyyy-MM-dd'))"
                $runs = $runs | Where-Object {
                    $localCopy = $_.copyRun | Where-Object { $_.target.type -eq 'kLocal' }
                    $runStart = (usecsToDate $localCopy.runStartTimeUsecs).Date
                    $runEnd   = (usecsToDate $localCopy.endTimeUsecs).Date
                    ($runStart -eq $snapshotDate.Date) -or ($runEnd -eq $snapshotDate.Date)
                }
                Write-DebugLog ("{0} runs matched snapshot date" -f $runs.Count)
                if ($runs.Count -eq 0) {
                    Write-Host "No snapshot runs found for the specified date: $($snapshotDate.ToString('yyyy-MM-dd'))." -ForegroundColor Yellow
                    continue
                }
            }

            $refDate = $null
            if ($lastSnapshotOfPreviousMonth -or $lastSnapshotOfCurrentMonth) {
                $month = if ($lastSnapshotOfPreviousMonth) { (Get-Date).AddMonths(-1) } else { Get-Date }
                $monthStart = Get-Date -Year $month.Year -Month $month.Month -Day 1
                $monthEnd   = $monthStart.AddMonths(1).AddDays(-1)

                $monthRuns = $runs | Where-Object {
                    $localCopy = $_.copyRun | Where-Object { $_.target.type -eq 'kLocal' }
                    $runStart = (usecsToDate $localCopy.runStartTimeUsecs).Date
                    $runEnd   = (usecsToDate $localCopy.endTimeUsecs).Date
                    if ($lastSnapshotOfPreviousMonth) {
                        ($runStart -ge $monthStart -and $runStart -le $monthEnd) -or
                        ($runEnd -ge $monthStart -and $runEnd -le $monthEnd)
                    } else {
                        ($runStart -ge $monthStart) -and ($runEnd -le $monthEnd)
                    }
                }

                $monthName = if ($lastSnapshotOfPreviousMonth) { "previous" } else { "current" }
                Write-DebugLog ("Found {0} runs in {1} month" -f $monthRuns.Count, $monthName)

                if ($monthRuns.Count -gt 0) {
                    # Sort month runs by end date descending
                    $sortedMonthRuns = @()
                    foreach ($mr in $monthRuns) {
                        $firstCopyRun = $mr.copyRun | Select-Object -First 1
                        $endDate = (usecsToDate $firstCopyRun.endTimeUsecs).Date
                        $sortedMonthRuns += [PSCustomObject]@{
                            Run = $mr
                            EndDate = $endDate
                        }
                    }
                    $sortedMonthRuns = $sortedMonthRuns | Sort-Object -Property EndDate -Descending
                    $runs = $sortedMonthRuns | Select-Object -First 1 | ForEach-Object { $_.Run }
                    
                    $localCopy = $runs.copyRun | Where-Object { $_.target.type -eq 'kLocal' }
                    $refDate = (usecsToDate $localCopy.endTimeUsecs).Date
                    Write-Host "Reference snapshot (last of $monthName month, using end date): $($refDate.ToString('yyyy-MM-dd'))"
                    Write-DebugLog "Reference snapshot date set to $refDate"
                } else {
                    Write-Host "No last snapshot found in the $monthName month ($($monthStart.ToString('MMMM yyyy')))." -ForegroundColor Yellow
                    Write-DebugLog "No reference snapshot found for $monthName month" "WARN"
                }
            }

            if (-not $refDate) {
                if ($StartDate -and $EndDate) {
                    $refDate = $StartDate
                } elseif ($snapshotDate) {
                    $refDate = $snapshotDate
                } else {
                    Write-Host "No reference snapshot found for job '$jobName', skipping retention calculation." -ForegroundColor Yellow
                    Write-DebugLog "Skipping job $jobName because no reference date was found" "WARN"
                    continue
                }
            }

            Write-DebugLog "Calculating retention days for job $jobName"
            if ($PSBoundParameters.ContainsKey('daysToKeep')) {
                $inclusionNote = "(Manual Override)"
                Write-DebugLog "Using manual daysToKeep: $daysToKeep"
            } elseif ($extendMonths) {
                $lastDayOfRefMonth = Get-Date -Year $refDate.Year -Month $refDate.Month -Day ([DateTime]::DaysInMonth($refDate.Year, $refDate.Month))
                $extendedMonth = $lastDayOfRefMonth.AddMonths($extendMonths)
                $lastDayExtendedMonth = Get-Date -Year $extendedMonth.Year -Month $extendedMonth.Month -Day ([DateTime]::DaysInMonth($extendedMonth.Year, $extendedMonth.Month))

                if ($includeSnapshotDay) {
                    $daysToKeep = ($lastDayExtendedMonth - $refDate).Days + 1
                    $inclusionNote = "(Snapshot Day Included)"
                } else {
                    $daysToKeep = ($lastDayExtendedMonth - $refDate).Days
                    $inclusionNote = "(Snapshot Day Excluded)"
                }
                Write-DebugLog ("Days to keep calculated: {0} {1}" -f $daysToKeep, $inclusionNote)
            }

            if ($runs.Count -gt 0) {
                Write-Host "Retention days calculated: $daysToKeep $inclusionNote"
                Write-Host "New snapshot expiration date: $($refDate.AddDays($daysToKeep).ToString('yyyy-MM-dd'))"
                Write-DebugLog ("New snapshot expiration date: {0}" -f $refDate.AddDays($daysToKeep).ToString('yyyy-MM-dd'))
                Write-Host ""
            }

            foreach ($run in $runs) {
                $localCopy = $run.copyRun | Where-Object { $_.target.type -eq 'kLocal' }
                $runDate = (usecsToDate $localCopy.runStartTimeUsecs).Date
                Write-DebugLog ("Processing run for $jobName on date $runDate")

                foreach ($copyRun in $run.copyRun | Where-Object { $_.target.type -eq 'kArchival' -and $_.status -eq 'kSuccess' }) {
                    if (!$target -or $copyRun.target.archivalTarget.vaultName -eq $target) {
                        $startTimeUsecs = $copyRun.runStartTimeUsecs
                        $newExpireTimeUsecs = $startTimeUsecs + ($daysToKeep * $usecsPerDay)
                        $currentExpireTimeUsecs = $copyRun.expiryTimeUsecs
                        $daysToExtend = [int64][math]::Round(($newExpireTimeUsecs - $currentExpireTimeUsecs) / $usecsPerDay)

                        Write-DebugLog ("Current expiry: {0}, new expiry: {1}, days to extend: {2}" -f (usecsToDate $currentExpireTimeUsecs), (usecsToDate $newExpireTimeUsecs), $daysToExtend)

                        if (!($daysToExtend -lt 0) -or $allowReduction) {
                            if ($daysToExtend -ne 0) {
                                $summary += [PSCustomObject]@{
                                    JobName      = $jobName
                                    RunDate      = $runDate
                                    OldExpiry    = usecsToDate($copyRun.expiryTimeUsecs)
                                    NewExpiry    = usecsToDate($newExpireTimeUsecs)
                                    DaysAdjusted = $daysToExtend
                                }

                                $msgBase = "    $($runDate.ToString('yyyy-MM-dd')): adjusting by $daysToExtend day(s)"
                                if ($DryRun) {
                                    Write-Host "$msgBase (DryRun)" -ForegroundColor Yellow
                                } else {
                                    Write-Host "$msgBase" -ForegroundColor Green
                                }

                                if ($commit -and -not $DryRun) {
                                    Write-DebugLog "Committing retention change to API..."
                                    $expireRun = @{
                                        'jobRuns'=@(@{
                                            'jobUid'            = $run.jobUid
                                            'runStartTimeUsecs' = $run.backupRun.stats.startTimeUsecs
                                            'copyRunTargets'    = @(@{
                                                'daysToKeep'     = $daysToExtend
                                                'type'           = 'kArchival'
                                                'archivalTarget' = $copyRun.target.archivalTarget
                                            })
                                        })
                                    }
                                    $response = api put protectionRuns $expireRun
                                    Write-DebugLog ("API response: " + ($response | ConvertTo-Json -Compress))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

if ($summary.Count -gt 0) {
    Write-Host ""
    $header = "{0,-25} {1,-12} {2,-12} {3,-12} {4,5}" -f "JobName","RunDate","OldExpiry","NewExpiry","DaysAdj"
    Write-Host $header -ForegroundColor Cyan
    Write-Host ("-" * ($header.Length)) -ForegroundColor Cyan
    foreach ($row in $summary) {
        Write-Host ("{0,-25} {1,-12} {2,-12} {3,-12} {4,5}" -f $row.JobName, $row.RunDate.ToString('yyyy-MM-dd'), $row.OldExpiry.ToString('yyyy-MM-dd'), $row.NewExpiry.ToString('yyyy-MM-dd'), $row.DaysAdjusted) -ForegroundColor Green
    }
    Write-Host ("=" * ($header.Length)) -ForegroundColor Cyan

    if ($SummaryCsv) {
        $summary | Export-Csv -Path $SummaryCsv -NoTypeInformation -Force
        Write-Host "Summary exported to CSV: $SummaryCsv" -ForegroundColor Cyan
        Write-DebugLog ("Summary exported to CSV: $SummaryCsv")
    }
} else {
    Write-Host "No archive runs matched the specified date(s)." -ForegroundColor Yellow
    Write-DebugLog "No archival runs matched the filters" "WARN"
}

Write-Host ""
if ($DryRun) {
    Write-Host "Dry Run complete - no changes were made." -ForegroundColor Yellow
} else {
    Write-Host "Retention adjustment complete."
}
