<#
.SYNOPSIS
Extends retention for archived snapshots to the end of the extended month.

.DESCRIPTION
Calculates a new snapshot expiration date based on a provided snapshot date, the last snapshot of the previous or current month, or a date range. Retention can be extended by months (-extendMonths), manually overridden (-daysToKeep), or defaults to end of month if -lastSnapshotOfPreviousMonth or -lastSnapshotOfCurrentMonth is used. Supports DryRun, commit, colored console summary, optional CSV export, and automatic debug logging.

.EXAMPLE
.\extendarchivetaskseom.ps1 -vip 10.100.0.11 -username admin -snapshotDate 2025-10-28 -extendMonths 1 -DryRun

.EXAMPLE
.\extendarchivetaskseom.ps1 -vip 10.100.0.11 -username admin -jobList "C:\jobs.txt" -policyList "C:\policies.txt" -extendMonths 1 -commit

.EXAMPLE
.\extendarchivetaskseom.ps1 -vip 10.100.0.11 -username admin -showExpiration 2025-12-31

.EXAMPLE
.\extendarchivetaskseom.ps1 -vip 10.100.0.11 -username admin -useApiKey -extendMonths 1 -commit

.EXAMPLE
.\extendarchivetaskseom.ps1 -vip 10.100.0.11 -username admin -useAPI -ApiKey 'xxxxxxxxxxxxxxxx' -extendMonths 1 -commit
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip = 'helios.cohesity.com',
    [Parameter(Mandatory = $True)][string]$username = 'helios',
    [Parameter()][string]$domain = 'local',

    [Parameter(Mandatory = $False)][int]$extendMonths,
    [Parameter(Mandatory = $False)][int]$daysToKeep,
    [Parameter(Mandatory = $False)][datetime]$snapshotDate,
    [Parameter(Mandatory = $False)][datetime]$StartDate,
    [Parameter(Mandatory = $False)][datetime]$EndDate,
    [Parameter(Mandatory = $False)][switch]$includeSnapshotDay,

    # Password is used for password auth OR carries the API key for API-key auth
    [Parameter()][string]$password,

    [Parameter()][switch]$noPrompt,

    # Allow both -useApiKey and -useAPI
    [Parameter()][Alias('useAPI')][switch]$useApiKey,

    # Optional explicit API key input; if omitted and -useApiKey is set, it will prompt unless -noPrompt is used
    [Parameter()][Alias('ApiToken','ApiSecret')][string]$ApiKey,

    [Parameter()][string]$mfaCode,
    [Parameter()][switch]$emailMfaCode,
    [Parameter()][switch]$mcm,
    [Parameter()][string]$region,
    [Parameter()][string]$tenant,
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
    [Parameter(Mandatory = $False)][datetime]$showExpiration
)

# Initialize log file with timestamp - create immediately
$logDate = Get-Date -Format "yyyyMMdd_HHmmss"
$scriptPath = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$logFile = Join-Path -Path $scriptPath -ChildPath "extendlog_$logDate.txt"

# Create the log file immediately
try {
    $null = New-Item -Path $logFile -ItemType File -Force -ErrorAction Stop
    Add-Content -Path $logFile -Value "Log file created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ErrorAction Stop
    Write-Host "Debug logging enabled. Log file: $logFile" -ForegroundColor Cyan
} catch {
    Write-Warning "Failed to create log file at $logFile. Error: $_"
    Write-Warning "Logging will be disabled."
    $logFile = $null
}

function Write-DebugLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    if ($null -eq $script:logFile) {
        return
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp][$Level] $Message"
    # Write to log file
    try {
        Add-Content -Path $script:logFile -Value $logMessage -ErrorAction Stop
    } catch {
        # Silently fail if logging doesn't work
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
    } catch {
        Write-Host "ERROR: Failed to read $ListType file: $FilePath - $_" -ForegroundColor Red
        Write-DebugLog "Failed to read $ListType file: $FilePath - $_" "ERROR"
        exit 1
    }
}

# Log script start
Write-DebugLog "========================================" "INFO"
Write-DebugLog "Script started" "INFO"
Write-DebugLog "Script path: $scriptPath" "INFO"
Write-DebugLog "Log file: $logFile" "INFO"
Write-DebugLog "Parameters: VIP=$vip, Username=$username, Domain=$domain" "INFO"
Write-DebugLog "Authentication: UseApiKey=$useApiKey, MCM=$mcm, Region=$region, Tenant=$tenant" "INFO"

if ($showExpiration) {
    Write-DebugLog "Mode: Show Expiration for date $($showExpiration.ToString('yyyy-MM-dd'))" "INFO"
} elseif ($extendMonths) {
    Write-DebugLog "Mode: Extend Retention by $extendMonths month(s)" "INFO"
} elseif ($daysToKeep) {
    Write-DebugLog "Mode: Set Retention to $daysToKeep days" "INFO"
}
Write-DebugLog "DryRun: $DryRun, Commit: $commit" "INFO"
Write-DebugLog "========================================" "INFO"
Write-Host ""

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

# Validate parameters - skip validation if showExpiration is used
if (-not $showExpiration) {
    if (-not ($lastSnapshotOfPreviousMonth -or $lastSnapshotOfCurrentMonth) -and
        (($PSBoundParameters.ContainsKey('daysToKeep') -and $PSBoundParameters.ContainsKey('extendMonths')) -or
         (-not $PSBoundParameters.ContainsKey('daysToKeep') -and -not $PSBoundParameters.ContainsKey('extendMonths')))) {
        Write-Host "ERROR: You must specify exactly ONE of -daysToKeep or -extendMonths." -ForegroundColor Red
        Write-DebugLog "Parameter validation failed: Must specify exactly ONE of -daysToKeep or -extendMonths" "ERROR"
        exit 1
    }
}

# --------------- Auth input handling (API key alias and prompting) ---------------
# Normalize and validate auth inputs prior to calling apiauth
if ($useApiKey) {
    # If ApiKey param provided, prefer it; otherwise, fall back to -password or prompt
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        if (-not [string]::IsNullOrWhiteSpace($password)) {
            $ApiKey = $password
            Write-DebugLog "Using API key from -password parameter (mapped)." "INFO"
        } elseif (-not $noPrompt) {
            # Prompt quietly for API key if not provided
            $secure = Read-Host -AsSecureString "Enter API Key"
            $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try {
                $ApiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
            } finally {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
            }
            Write-DebugLog "API key captured via prompt." "INFO"
        } else {
            Write-Host "ERROR: -useApiKey specified but no API key provided and -noPrompt is set." -ForegroundColor Red
            Write-DebugLog "API key missing with -noPrompt." "ERROR"
            exit 1
        }
    }

    # Map API key into -password variable used by apiauth
    $password = $ApiKey

    # Optional: clear ApiKey variable after mapping for safety
    $ApiKey = $null
} else {
    # Password auth path: ensure we don't accidentally mix ApiKey with password auth
    if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
        Write-Host "ERROR: -ApiKey provided without -useApiKey. Did you mean to use -useApiKey (or -useAPI)?" -ForegroundColor Red
        Write-DebugLog "ApiKey provided without -useApiKey." "ERROR"
        exit 1
    }

    # If password is required and not provided, prompt unless -noPrompt
    if ([string]::IsNullOrWhiteSpace($password) -and -not $noPrompt) {
        $secure = Read-Host -AsSecureString "Enter Password"
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }
        Write-DebugLog "Password captured via prompt." "INFO"
    }
}
# -------------------------------------------------------------------------------

. $(Join-Path -Path $scriptPath -ChildPath cohesity-api.ps1)
Write-DebugLog "Loaded cohesity-api.ps1"
Write-Host "Connecting to Cohesity cluster $vip..."
if ($useApiKey) {
    Write-Host "Using API Key authentication..." -ForegroundColor Cyan
    Write-DebugLog "Attempting API Key authentication with user $username@$domain"
} else {
    Write-Host "Using password authentication..." -ForegroundColor Cyan
    Write-DebugLog "Attempting password authentication with user $username@$domain"
}

# Authenticate with support for API key, MFA, MCM, etc.
apiauth -vip $vip `
    -username $username `
    -domain $domain `
    -passwd $password `
    -apiKeyAuthentication $useApiKey `
    -mfaCode $mfaCode `
    -sendMfaCode $emailMfaCode `
    -heliosAuthentication $mcm `
    -regionid $region `
    -tenant $tenant `
    -noPromptForPassword $noPrompt

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
$expirationList = @()
$usecsPerDay = 86400000000

# If showExpiration is specified, run in display-only mode
if ($showExpiration) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Searching for snapshots expiring on: $($showExpiration.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-DebugLog "Starting expiration search for date: $($showExpiration.ToString('yyyy-MM-dd'))"

    $targetExpirationDate = $showExpiration.Date

    foreach ($job in $jobs | Sort-Object -Property name) {
        Write-DebugLog "Processing job: $($job.name)"
        $policy = $policies | Where-Object { $_.id -eq $job.policyId }

        if (!$policyNames -or ($policy -and $policy.name -in $policyNames)) {
            $jobName = $job.name
            if (!$jobNames -or $job.name -in $jobNames) {
                Write-DebugLog "Fetching archival runs for job $jobName..."
                $apiUrl = "protectionRuns?jobId=$($job.id)&excludeTasks=true&excludeNonRestoreableRuns=true&numRuns=999999&runTypes=kRegular"
                $allRuns = api get $apiUrl
                $runs = $allRuns | Where-Object { 'kArchival' -in $_.copyRun.target.type }
                Write-DebugLog ("Found {0} archival runs for job $jobName" -f $runs.Count)

                foreach ($run in $runs) {
                    $localCopy = $run.copyRun | Where-Object { $_.target.type -eq 'kLocal' }
                    if ($localCopy) {
                        $runDate = (usecsToDate $localCopy.runStartTimeUsecs).Date
                        foreach ($copyRun in $run.copyRun | Where-Object { $_.target.type -eq 'kArchival' -and $_.status -eq 'kSuccess' }) {
                            if (!$target -or $copyRun.target.archivalTarget.vaultName -eq $target) {
                                $expiryDate = (usecsToDate $copyRun.expiryTimeUsecs).Date
                                if ($expiryDate -eq $targetExpirationDate) {
                                    $vaultName = $copyRun.target.archivalTarget.vaultName
                                    $expirationList += [PSCustomObject]@{
                                        JobName        = $jobName
                                        PolicyName     = if ($policy) { $policy.name } else { "N/A" }
                                        SnapshotDate   = $runDate
                                        ExpirationDate = $expiryDate
                                        VaultName      = $vaultName
                                        RunStartTime   = usecsToDate $localCopy.runStartTimeUsecs
                                    }
                                    Write-DebugLog "Found matching snapshot: Job=$jobName, Date=$runDate, Vault=$vaultName"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    # Display results
    if ($expirationList.Count -gt 0) {
        Write-Host ""
        Write-Host "Found $($expirationList.Count) snapshot(s) expiring on $($showExpiration.ToString('yyyy-MM-dd')):" -ForegroundColor Green
        Write-Host ""
        Write-DebugLog "Total snapshots found: $($expirationList.Count)"

        $header = "{0,-30} {1,-20} {2,-15} {3,-15} {4,-20}" -f "JobName","PolicyName","SnapshotDate","ExpiryDate","VaultName"
        Write-Host $header -ForegroundColor Cyan
        Write-Host ("-" * 100) -ForegroundColor Cyan

        foreach ($item in $expirationList | Sort-Object -Property JobName, SnapshotDate) {
            Write-Host ("{0,-30} {1,-20} {2,-15} {3,-15} {4,-20}" -f `
                $item.JobName, `
                $item.PolicyName, `
                $item.SnapshotDate.ToString('yyyy-MM-dd'), `
                $item.ExpirationDate.ToString('yyyy-MM-dd'), `
                $item.VaultName) -ForegroundColor White

            Write-DebugLog ("Result: Job=$($item.JobName), Policy=$($item.PolicyName), Snapshot=$($item.SnapshotDate.ToString('yyyy-MM-dd')), Expiry=$($item.ExpirationDate.ToString('yyyy-MM-dd')), Vault=$($item.VaultName)")
        }

        Write-Host ("=" * 100) -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Total snapshots found: $($expirationList.Count)" -ForegroundColor Green

        # Export to CSV if specified
        if ($SummaryCsv) {
            $expirationList | Export-Csv -Path $SummaryCsv -NoTypeInformation -Force
            Write-Host "Results exported to CSV: $SummaryCsv" -ForegroundColor Cyan
            Write-DebugLog "Expiration list exported to CSV: $SummaryCsv"
        }
    } else {
        Write-Host "No snapshots found expiring on $($showExpiration.ToString('yyyy-MM-dd'))." -ForegroundColor Yellow
        Write-DebugLog "No snapshots found for expiration date $($showExpiration.ToString('yyyy-MM-dd'))" "WARN"
    }

    Write-DebugLog "Expiration search completed"
    Write-DebugLog "========================================" "INFO"

    if ($logFile) {
        Write-Host ""
        Write-Host "Debug log saved to: $logFile" -ForegroundColor Cyan
    }

    # Exit after displaying expiration information
    exit 0
}

# Normal retention extension logic (existing code continues below)
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
                    Run     = $r
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
                            Run     = $mr
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
    Write-Host ("=" * 100) -ForegroundColor Cyan
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
    Write-DebugLog "Dry run completed - no changes committed"
} else {
    Write-Host "Retention adjustment complete." -ForegroundColor Green
    Write-DebugLog "Retention adjustment completed"
}

Write-DebugLog "========================================" "INFO"
Write-DebugLog "Script completed successfully" "INFO"

if ($logFile) {
    Write-Host ""
    Write-Host "Debug log saved to: $logFile" -ForegroundColor Cyan
}
