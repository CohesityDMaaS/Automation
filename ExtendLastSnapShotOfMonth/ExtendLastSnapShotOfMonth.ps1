# Enable advanced functions features like CmdletBinding and parameter validation
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip,
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$domain = 'local',
    [Parameter()][array]$jobname,
    [Parameter()][string]$jobList = '',
    [Parameter()][array]$policyName,
    [Parameter()][string]$policyList,
    [Parameter()][switch]$includeReplicas,
    [Parameter()][switch]$commit,
    [Parameter(Mandatory = $True)][int]$extendMonths,
    [Parameter()][switch]$IncludeSnapshotDay,
    [Parameter()][switch]$IncludeCrossMonth,
    [Parameter()][switch]$IncludeReverseCrossMonth,
    [Parameter()][string]$LogPath,
    [Parameter()][switch]$DryRun
)

# -------------------------------------------------------------
# Ensure either DryRun or Commit is selected
# -------------------------------------------------------------
if (-not $DryRun -and -not $commit) {
    Write-Error "You must specify either -DryRun or -Commit. Exiting."
    exit
}

# -------------------------------------------------------------
# Auto-generate log filename if not specified
# -------------------------------------------------------------
if (-not $LogPath -or $LogPath -eq '') {
    $timestamp = (Get-Date -Format "yyyy-MM-dd_HHmm")
    $LogPath = "extendLog_$timestamp.txt"
}

$logFullPath = Join-Path -Path $PWD -ChildPath $LogPath

# Ensure log file exists
if (-not (Test-Path $logFullPath)) {
    "" | Out-File -FilePath $logFullPath -Encoding UTF8
}

# -------------------------------------------------------------
# Gather job and policy lists
# -------------------------------------------------------------
$jobsToUpdate = @()
foreach($job in $jobName){ $jobsToUpdate += $job }

if ('' -ne $jobList -and (Test-Path -Path $jobList -PathType Leaf)) {
    $jobsToUpdate += Get-Content $jobList | ForEach-Object { $_.Trim() }
}

$policiesToUpdate = @()
foreach($policy in $policyName){ $policiesToUpdate += $policy }

if ('' -ne $policyList -and (Test-Path -Path $policyList -PathType Leaf)) {
    $policiesToUpdate += Get-Content $policyList | ForEach-Object { $_.Trim() }
}

Write-Verbose "Jobs to update: $($jobsToUpdate -join ', ')"
Write-Verbose "Policies to update: $($policiesToUpdate -join ', ')"

# -------------------------------------------------------------
# Load Cohesity API helper and authenticate
# -------------------------------------------------------------
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)
apiauth -vip $vip -username $username -domain $domain
Write-Verbose "Authenticated with Cohesity cluster $vip"

# -------------------------------------------------------------
# Retrieve jobs and policies
# -------------------------------------------------------------
$jobs = (api get -v2 data-protect/protection-groups).protectionGroups | Where-Object isDeleted -ne $True
if ($jobsToUpdate) { $jobs = $jobs | Where-Object name -in $jobsToUpdate }
if (!$includeReplicas) { $jobs = $jobs | Where-Object isActive -eq $True }

$policies = (api get -v2 data-protect/policies).policies
if ($policiesToUpdate) {
    $policies = $policies | Where-Object name -in $policiesToUpdate
    $jobs = $jobs | Where-Object { $_.policyId -in @($policies.id) }
}

Write-Verbose "Jobs retrieved and filtered: $($jobs.Count)"

# -------------------------------------------------------------
# Calculate retention period
# -------------------------------------------------------------
$today = Get-Date
$firstDayOfThisMonth = Get-Date -Year $today.Year -Month $today.Month -Day 1
$lastDayPrevMonth = $firstDayOfThisMonth.AddDays(-1)

$lastDayExtendedMonth = $lastDayPrevMonth.AddMonths($extendMonths)
$lastDayExtendedMonth = Get-Date -Year $lastDayExtendedMonth.Year -Month $lastDayExtendedMonth.Month -Day ([DateTime]::DaysInMonth($lastDayExtendedMonth.Year, $lastDayExtendedMonth.Month))

if ($IncludeSnapshotDay) {
    $daysToKeep = ($lastDayExtendedMonth - $lastDayPrevMonth).Days + 1
    $inclusionNote = "(Snapshot Day Included)"
} else {
    $daysToKeep = ($lastDayExtendedMonth - $lastDayPrevMonth).Days
    $inclusionNote = "(Snapshot Day Excluded)"
}

$usecsPerDay = 86400000000

# -------------------------------------------------------------
# Display header info
# -------------------------------------------------------------
Write-Host ""
Write-Host "📅 Retention Calculation Summary" -ForegroundColor Cyan
Write-Host "-------------------------------------------"
Write-Host ("Last snapshot of previous month: {0}" -f $lastDayPrevMonth.ToString('yyyy-MM-dd'))
Write-Host ("Extending retention to:          {0}" -f $lastDayExtendedMonth.ToString('yyyy-MM-dd'))
Write-Host ("Days to keep:                    {0} {1}" -f $daysToKeep, $inclusionNote)
Write-Host ("Retention extension:             {0} month(s)" -f $extendMonths)
if ($DryRun) {
    Write-Host ("⚠️  DRY RUN MODE ACTIVE") -ForegroundColor Yellow -BackgroundColor DarkRed
} else {
    Write-Host ("✅ COMMIT MODE ACTIVE") -ForegroundColor Green
}
Write-Host ("Log file:                        {0}" -f $logFullPath)
Write-Host ""

# -------------------------------------------------------------
# Prepare logging
# -------------------------------------------------------------
"`nScript started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n" | Out-File -FilePath $logFullPath -Append
if ($DryRun) {
    "⚠️  THIS RUN IS A DRY RUN. NO CHANGES WERE MADE.`n" | Out-File -FilePath $logFullPath -Append
} else {
    "✅ CHANGES WILL BE COMMITTED.`n" | Out-File -FilePath $logFullPath -Append
}
"Retention extended by $extendMonths month(s) $inclusionNote`n" | Out-File -FilePath $logFullPath -Append

$results = @()

# -------------------------------------------------------------
# Process each job
# -------------------------------------------------------------
foreach ($job in $jobs | Sort-Object -Property name) {

    Write-Verbose "Processing job $($job.name)"

    # Define start/end window for last day of previous month
    $startTimeUsecs = [int64]((Get-Date $lastDayPrevMonth -Hour 0 -Minute 0 -Second 0).ToUniversalTime() - [datetime]'1970-01-01').TotalMilliseconds * 1000
    $endTimeUsecs = [int64]((Get-Date $lastDayPrevMonth.AddDays(1) -Hour 23 -Minute 59 -Second 59).ToUniversalTime() - [datetime]'1970-01-01').TotalMilliseconds * 1000

    $runs = (api get -v2 "data-protect/protection-groups/$($job.id)/runs?startTimeUsecs=$startTimeUsecs&endTimeUsecs=$endTimeUsecs&numRuns=9999&includeObjectDetails=false&runTypes=kSystem,kIncremental,kFull").runs
    Write-Verbose "Retrieved $($runs.Count) runs for $($job.name) in window"

    # Filter runs starting or ending on last day, cross-month included if requested
    $latestRun = $runs |
        Where-Object {
            $runStartDate = (usecsToDate $_.localBackupInfo.startTimeUsecs).Date
            $runEndDate = (usecsToDate $_.localBackupInfo.endTimeUsecs).Date
            ($runStartDate -eq $lastDayPrevMonth.Date) -or
            ($IncludeCrossMonth -and $runStartDate -lt $lastDayPrevMonth.Date -and $runEndDate -eq $lastDayPrevMonth.Date) -or
            ($IncludeReverseCrossMonth -and $runStartDate -eq $lastDayPrevMonth.Date -and $runEndDate -gt $lastDayPrevMonth.Date)
        } |
        Sort-Object { usecsToDate $_.localBackupInfo.startTimeUsecs } -Descending |
        Select-Object -First 1

    if (-not $latestRun) {
        Write-Verbose "No applicable run found for $($job.name)"
        continue
    }

    $runStartUsecs = if ($latestRun.isReplicationRun) { $latestRun.originalBackupInfo.startTimeUsecs } else { $latestRun.localBackupInfo.startTimeUsecs }
    $thisrun = api get "/backupjobruns?allUnderHierarchy=true&exactMatchStartTimeUsecs=$runStartUsecs&excludeTasks=true&id=$($job.id.split(':')[-1])"
    $currentExpireTimeUsecs = ($thisrun.backupJobRuns.protectionRuns[0].copyRun.finishedTasks | Where-Object {$_.snapshotTarget.type -eq 1}).expiryTimeUsecs
    $newExpireTimeUsecs = $runStartUsecs + ($daysToKeep * $usecsPerDay)
    $daysToExtend = [int][math]::Round(($newExpireTimeUsecs - $currentExpireTimeUsecs) / $usecsPerDay)

    $snapshotDate = (usecsToDate $runStartUsecs).ToString('yyyy-MM-dd')
    $currentExpireDate = (usecsToDate $currentExpireTimeUsecs).ToString('yyyy-MM-dd')
    $newExpireDate = (usecsToDate $newExpireTimeUsecs).ToString('yyyy-MM-dd')

    Write-Verbose "$($job.name) snapshot: $snapshotDate, current expiry: $currentExpireDate, new expiry: $newExpireDate"

    $results += [pscustomobject]@{
        JobName           = $job.name
        SnapshotDate      = $snapshotDate
        CurrentExpiryDate = $currentExpireDate
        NewExpiryDate     = $newExpireDate
        DaysExtended      = $daysToExtend
    }

    # Commit retention changes if requested
    if ($commit -and $daysToExtend -gt 0) {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        "$timestamp - $($job.name): $snapshotDate ($currentExpireDate -> $newExpireDate)" | Out-File -FilePath $logFullPath -Append

        $runParameters = @{
            "jobRuns" = @(
                @{
                    "jobUid" = @{
                        "clusterId" = $thisrun.backupJobRuns.protectionRuns[0].copyRun.jobUid.clusterId;
                        "clusterIncarnationId" = $thisrun.backupJobRuns.protectionRuns[0].copyRun.jobUid.clusterIncarnationId;
                        "id" = $thisrun.backupJobRuns.protectionRuns[0].copyRun.jobUid.objectId
                    }
                    "runStartTimeUsecs" = $runStartUsecs;
                    "copyRunTargets" = @(
                        @{
                            "daysToKeep" = [int]$daysToExtend;
                            "type" = "kLocal"
                        }
                    )
                }
            )
        }
        $null = api put protectionRuns $runParameters
    }
}

# -------------------------------------------------------------
# Output summary table
# -------------------------------------------------------------
if ($results.Count -gt 0) {
    Write-Host ""
    Write-Host "✅ Retention Extension Summary" -ForegroundColor Cyan
    Write-Host "---------------------------------------------------------------"
    Write-Host ("{0,-30} {1,-12} {2,-12} {3,-12} {4,5}" -f "Job Name", "Snapshot", "Current Exp", "New Exp", "Days") -ForegroundColor White
    Write-Host ("{0,-30} {1,-12} {2,-12} {3,-12} {4,5}" -f "--------", "--------", "-----------", "-------", "----") -ForegroundColor White

    $totalJobs = $results.Count
    $totalJobsExtended = 0
    $totalDaysExtended = 0
    $logLines = @()
    $logLines += "Retention Extension Summary"
    $logLines += "---------------------------------------------------------------"
    $logLines += "{0,-30} {1,-12} {2,-12} {3,-12} {4,5}" -f "Job Name", "Snapshot", "Current Exp", "New Exp", "Days"
    $logLines += "{0,-30} {1,-12} {2,-12} {3,-12} {4,5}" -f "--------", "--------", "-----------", "-------", "----"

    foreach ($row in $results | Sort-Object JobName) {
        $line = "{0,-30} {1,-12} {2,-12} {3,-12} {4,5}" -f $row.JobName, $row.SnapshotDate, $row.CurrentExpiryDate, $row.NewExpiryDate, $row.DaysExtended
        if ($row.DaysExtended -gt 0) {
            Write-Host $line -ForegroundColor Green
            $totalJobsExtended++
            $totalDaysExtended += $row.DaysExtended
        } else {
            Write-Host $line -ForegroundColor Yellow
        }
        $logLines += $line
    }

    Write-Host "---------------------------------------------------------------"
    Write-Host ("Total Jobs: {0}, Extended: {1}, Total Days Extended: {2}" -f $totalJobs, $totalJobsExtended, $totalDaysExtended) -ForegroundColor Cyan

    $logLines += "---------------------------------------------------------------"
    $logLines += "Total Jobs: $totalJobs, Extended: $totalJobsExtended, Total Days Extended: $totalDaysExtended"

    if ($DryRun) { $logLines += "⚠️  THIS RUN WAS A DRY RUN. NO CHANGES WERE MADE." } else { $logLines += "✅ CHANGES WERE COMMITTED." }

    $logLines | Out-File -FilePath $logFullPath -Encoding UTF8
} else {
    Write-Host ""
    Write-Warning "No applicable snapshots found for retention extension."
    "No applicable snapshots found for retention extension." | Out-File -FilePath $logFullPath -Encoding UTF8
    if ($DryRun) { "⚠️  THIS RUN WAS A DRY RUN. NO CHANGES WERE MADE." | Out-File -FilePath $logFullPath -Append } else { "✅ CHANGES WERE COMMITTED." | Out-File -FilePath $logFullPath -Append }
}
