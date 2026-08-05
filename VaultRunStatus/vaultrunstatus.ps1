######################################################################################################################################################################################################################
#This Script ## the following tasks:
#The sole purpose is to collect data related to backup and archive operations for multiple clusters and writing this information to separate CSV, xlsx, and html files for each cluster. The records are
#formatted with the appropriate columns, and the report is sorted by the "Run Date" column in descending order before being written to the output file.
#
#It iterates over a list of cluster names stored in the $clusternames array.
#
#For each cluster, it creates an output file with a name that includes the cluster name and the current date.
#
#It writes the header row to the output file, defining the columns for the report.( Useful information like: Protection Group name, The Backup Run Status, client Name(VM, View, NAS, etc.), The Client
# Type, The Job Run Date, When the local backup expires, The external Archive Target(FortKnox), Archive Run Status, Archive Expiry Date, Physical Data Transferred, Logical Archive Transferred, Average Archive Throughput"
#
#It retrieves a list of backup jobs for the current cluster using Cohesity API calls and processes the information for each job.
#
#For each job, it retrieves information about the runs and archives associated with the job, extracting various details, such as object names, run status, client names, and archive information.
#
#It formats the extracted data and appends it to the output file as a CSV record, as well as excel and html - Optionally you can comment out any of the export (file creation steps and export steps) blocks below.
#
#The script continues to process data for each job in the cluster.
#
#After all jobs in the cluster have been processed, it prints a message indicating that the output for that cluster has been written to the file.
#
#
#The script relies on the "coheisty-api.ps1" script for successful execution.
######################################################################################################################################################################################################################
# process command line arguments
[CmdletBinding()]
param (
    [Parameter()][string]$apiKey = '',  # apiKey
    [Parameter()][string]$vip = 'helios.cohesity.com',
    [Parameter()][string]$username = '',
    [Parameter()][string]$domain = 'local',
    [Parameter()][string]$tenant = $null,
    [Parameter()][switch]$useApiKey,
    [Parameter()][string]$password = $null,
    [Parameter()][switch]$noPrompt,
    [Parameter()][switch]$mcm,
    [Parameter()][string]$mfaCode = $null,
    [Parameter()][switch]$emailMfaCode,
    [Parameter()][string]$clusterName = $null, #specify a specific cluster replacing $null with the name, otherwise all clusters connected to the Helios Tenant will be in scope
    [Parameter()][int]$numRuns = 1000,
    [Parameter()][ValidateSet('MiB','GiB')][string]$unit = 'MiB',
    [Parameter()][string]$ExternalTarget = '', #only report vaulting runs whose external target matches this name (checked against ownershipContext, then targetName). Leave blank to include all external targets.
    [Parameter()][string]$duration = '1d', #how far back to pull runs from - e.g. '24h', '2d', '3d', '1w', '1m' (hours/days/weeks/months)
    [Parameter()][ValidateSet('Successful','Running','Failed','Canceled')][string[]]$ArchiveRunStatus = @() #only report runs with these Archive Run Status value(s). Leave blank to include all statuses.
)
$conversion = @{'Kib' = 1024; 'MiB' = 1024 * 1024; 'GiB' = 1024 * 1024 * 1024; 'TiB' = 1024 * 1024 * 1024 * 1024}
function toUnits($val){
    return "{0:n0}" -f ($val/($conversion[$unit]))
}
# Unit label for the Average Throughput column. This is megabits-per-second (from the API's
# avgLogicalTransferRateBps stat), which is a different unit family than the MiB/GiB used for
# Physical/Logical Transferred, so it's tracked separately from -unit.
$UnitTP = 'Mbps'
function Convert-BpsToMbps {
    param (
        [double]$bps
    )
    $mbps = $bps / 1e6  # 1 Mbps = 1,000,000 bps
    return $mbps
}
# HTML row styling helper - highlights failed statuses in red, succeeded in green
function Get-HtmlStatusClass($status){
    if($status -match 'Fail'){ return 'status-fail' }
    if($status -match 'Success|Succeeded'){ return 'status-ok' }
    return ''
}
# HTML-escape helper so object/job names with special characters don't break the table
function ConvertTo-HtmlSafe($text){
    if($null -eq $text){ return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$text)
}
# Only vaulting runs matching -ExternalTarget should appear in the report. Leave -ExternalTarget
# blank (the default) to include every external target. Cohesity flags vault ownership via the
# archive result's ownershipContext field (e.g. Local / FortKnox), which is independent of
# whatever name was given to the external target, so it's checked first. targetName is kept as a
# fallback in case ownershipContext isn't populated, or -ExternalTarget is being used to match a
# target by its configured name instead.
function Test-ExternalTargetFilter($archiveResult){
    if([string]::IsNullOrWhiteSpace($ExternalTarget)){ return $true }
    if($archiveResult.ownershipContext -eq $ExternalTarget){ return $true }
    if($archiveResult.targetName -match [regex]::Escape($ExternalTarget)){ return $true }
    return $false
}
# Maps the friendly -ArchiveRunStatus values to the regex patterns used to match against
# whatever raw status string Cohesity returns (e.g. "kSuccess"/"Succeeded", "kCanceled", etc.)
$ArchiveStatusAliases = @{
    'Successful' = 'Success|Succeeded'
    'Running'    = 'Running'
    'Failed'     = 'Fail'
    'Canceled'   = 'Cancel'
}
# Only runs matching -ArchiveRunStatus should appear in the report. Leave -ArchiveRunStatus
# blank (the default) to include every status. Pass one or more of Successful/Running/Failed/Canceled.
function Test-ArchiveStatusFilter($status){
    if($ArchiveRunStatus.Count -eq 0){ return $true }
    foreach($requested in $ArchiveRunStatus){
        $pattern = $ArchiveStatusAliases[$requested]
        if(!$pattern){ $pattern = [regex]::Escape($requested) }
        if($status -match $pattern){ return $true }
    }
    return $false
}
# Parses -duration (e.g. '24h', '2d', '3d', '1w', '1m') into a start DateTime that many
# hours/days/weeks/months before now. Supports h/hr/hrs/hour/hours, d/day/days, w/wk/week/weeks,
# and m/mo/month/months as unit suffixes.
function Get-DurationStartDate($duration){
    if($duration -notmatch '^\s*(\d+)\s*([a-zA-Z]+)\s*$'){
        Write-Host "Invalid -duration value '$duration'. Expected formats like 24h, 2d, 3d, 1w, 1m." -ForegroundColor Yellow
        exit 1
    }
    $value = [int]$Matches[1]
    $unit = $Matches[2].ToLower()
    switch -regex ($unit){
        '^h(r|rs|our|ours)?$'  { return (Get-Date).AddHours(-$value) }
        '^d(ay|ays)?$'         { return (Get-Date).AddDays(-$value) }
        '^w(k|ks|eek|eeks)?$'  { return (Get-Date).AddDays(-7 * $value) }
        '^mo?(nth|nths)?$'     { return (Get-Date).AddMonths(-$value) }
        default {
            Write-Host "Unrecognized -duration unit '$unit'. Use h/d/w/m for hours/days/weeks/months." -ForegroundColor Yellow
            exit 1
        }
    }
}
# source the cohesity-api helper code
. $(Join-Path -Path .\ -ChildPath cohesity-api.ps1)
# authenticate
apiauth -vip $vip -username $username -domain $domain -passwd $password -apiKeyAuthentication $useApiKey -mfaCode $mfaCode -sendMfaCode $emailMfaCode -heliosAuthentication $mcm -regionid $region -tenant $tenant -noPromptForPassword $noPrompt
# Validate Authentication
if(!$cohesity_api.authorized){
    Write-Host "Not authenticated" -ForegroundColor Yellow
    exit 1
}
# If a cluster name was not previously inputted -Get list of clusters from Helios
  if ($Clustername) {
  $clusternames = $clusterName
    }elseif ($cohesity_api.heliosConnectedClusters.name -and !$clusterName) {
        $thisCluster = heliosCluster $cohesity_api.heliosConnectedClusters.name[0]
            if(!$clustername){$clusternames = $cohesity_api.heliosConnectedClusters.name}
    } elseif ($clusterName) {
        $thisCluster = heliosCluster $clusterName
    } else {
        Write-Host "Please provide -clusterName when connecting through helios" -ForegroundColor Yellow
        exit 1
 }
 if(!(helioscluster $clusterName) -contains "Cluster $clustername not connected to Helios"){
 Write-host "Check to ensure the clustername $clustername input is correct or ensure the cluster is connected to helios" -ForegroundColor Red
 exit 1
}

# Run the report against each cluster
ForEach($clusterName in $clusternames){
# Create the CSV  outfile- You can comment out the below lines if you prefer to use the Excel export option below
Write-Host "Creating output csv file for Cluster $Clustername" -ForegroundColor Green
$dateString = (get-date).ToString('yyyy-MM-dd')
$outfileNamecsv = "vaultInventory-$($clustername)-$dateString.csv"

# Define the excel output file path- You can comment out the below lines if you prefer to use the CSV option above
# Module ImportExcel is required
$outfileNamexlsx = "vaultInventory-$($clustername)-$dateString.xlsx"

# Define the html output file path- You can comment out the below lines if you don't want an html report
# Generated automatically for every cluster, alongside the csv and xlsx exports
$outfileNamehtml = "vaultInventory-$($clustername)-$dateString.html"

# Diagnostics for the FortKnox filter - tracks every distinct target seen and how many rows matched,
# so if the report comes back empty we can print exactly what ownershipContext/targetName values
# this cluster is actually returning instead of guessing again.
$matchedRowCount = 0
$seenTargets = New-Object System.Collections.Generic.HashSet[string]

# Create the csv output report headings- You can comment out the below lines if you prefer to use the Excel Option
if ($outfileNamecsv -ne $null){
"Job Name,Backup Run Status,client Name,Object Type,Run Date,Backup Expiry Date,External Target,Archive Run Status,Archive Expiry Date,Physical Transferred ($unit),Logical Transferred ($unit),Average Throughput ($unitTP),Vaulting Process Duration,Failure Reason"  | Out-File -FilePath $outfileNamecsv -Encoding utf8
}

# Create the html output report - write the page shell, styling and table header row
if ($outfileNamehtml -ne $null){
    Write-Host "Creating output html file for Cluster $Clustername" -ForegroundColor Green
    $htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Vault Inventory - $clusterName - $dateString</title>
<style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 20px; color: #222; }
    h1 { font-size: 20px; }
    table { border-collapse: collapse; width: 100%; font-size: 12px; }
    th, td { border: 1px solid #ccc; padding: 6px 8px; text-align: left; white-space: nowrap; }
    th { background-color: #2c3e50; color: #fff; position: sticky; top: 0; }
    tr:nth-child(even) { background-color: #f7f7f7; }
    .status-ok { color: #1a7f37; font-weight: bold; }
    .status-fail { color: #c0392b; font-weight: bold; }
</style>
</head>
<body>
<h1>Vault Inventory Report - Cluster: $clusterName - $dateString</h1>
<table>
<thead>
<tr>
<th>Job Name</th><th>Backup Run Status</th><th>client Name</th><th>Object Type</th><th>Run Date</th><th>Backup Expiry Date</th><th>External Target</th><th>Archive Run Status</th><th>Archive Expiry Date</th><th>Physical Transferred ($unit)</th><th>Logical Transferred ($unit)</th><th>Average Throughput (Mbps)</th><th>Vaulting Process Duration</th><th>Failure Reason</th>
</tr>
</thead>
<tbody>
"@
    $htmlHeader | Out-File -FilePath $outfileNamehtml -Encoding utf8
}

# Resolve -duration into a startTimeUsecs bound so the runs query only pulls back that far,
# instead of relying on whatever implicit lookback window the API defaults to.
$reportStartDate = Get-DurationStartDate $duration
$startUsecs = dateToUsecs $reportStartDate
Write-Host "Report will include runs from $reportStartDate to now (duration: $duration)" -ForegroundColor Green
# Get list of jobs for the Cluster
$thisCluster = heliosCluster $clusterName
Write-Host "Fetching list of Backup Jobs for Cluster $Clustername" -ForegroundColor Green
$jobs = api get -v2 "data-protect/protection-groups?includeTenants=true&isActive=true&isDeleted=false&isPaused=false"
Write-Host "Processing job to extract backup and archive details for Cluster $Clustername" -ForegroundColor Green
foreach ($job in $jobs.protectionGroups | Sort-Object -Property name){
    $endUsecs = dateToUsecs (Get-Date)
            $runs = api get -v2 "data-protect/protection-groups/$($job.id)/runs?numRuns=$numRuns&startTimeUsecs=$startUsecs&endTimeUsecs=$endUsecs&includeTenants=true&includeObjectDetails=true"
                 ForEach ($run in $runs.runs){

                        $objectnames = $run.objects.object.name
                        $ObjectIDs = $run.objects.object.id
                        $ObjectSourceIds = $run.objects.object.sourceId
                        $ObjectOSTypes = $run.objects.object.osType
                        $Objectenvironments = $run.objects.object.environment
                        $runId = $run.id
                        $runstatus = $run.localBackupInfo.status
                        $jobname = $run.protectionGroupName

               # Get the client names of each run of the job
                $runobjects = $run.objects
                    foreach($object in $runobjects){
                        if($ObjectFailureResult){
                        Clear-Variable ObjectFailureResult
                        }
                        $objectname = $object.object.name
                        $ObjectID = $object.object.id
                        $ObjectSourceId = $object.object.sourceId
                        $ObjectOSType = $object.object.osType
                        $Objectenvironment = $object.object.environment
                        $ObjectStatusRaw = $Object.localSnapshotInfo.snapshotInfo.status
                        if($ObjectStatusRaw){
                            $ObjectRunStatus = $ObjectStatusRaw.Split("k")[-1]
                        }else{
                            $ObjectRunStatus = $null
                        }
                            if($ObjectRunStatus -eq "Failed"){
                        $ObjectFailedReason = $object.localSnapshotInfo.failedAttempts.Message[3]
                        $ObjectFailedAttempts = $object.localSnapshotInfo.failedAttempts.count
                            }
                             if($ObjectRunStatus -eq "Failed"){
                        $ObjectFailureResult = "$ObjectFailedAttempts backup attempts were made but failed due to: $ObjectFailedReason"
                        }
                        $backupexpiry = usecsToDate $object.localsnapshotinfo.snapshotInfo.expiryTimeUsecs

               # Capture Local backup details

                 if($run.PSObject.Properties['localSnapshotInfo']){
                        $runStartTimeUsecs = $object.localsnapshotinfo.snapshotInfo.startTimeUsecs
                        $runEndTimeUsecs = $object.localsnapshotinfo.snapshotInfo.endTimeUsecs
                    }else{
                        $runStartTimeUsecs = $run.localBackupInfo.startTimeUsecs
                        $runEndTimeUsecs = $run.localBackupInfo.endTimeUsecs
                    }
                        # Calculate duration
                            $StartEndDelta = ($runEndTimeUsecs - $runStartTimeUsecs) / 1e6
                        # Convert seconds to time duration
                            $runDuration = [TimeSpan]::FromSeconds($StartEndDelta)
                        # Format the Time to HH:MM:SS
                            $JobDuration = $runDuration.ToString("hh\:mm\:ss")
                        $runStartTime = usecsToDate $runStartTimeUsecs
                        $runEndTime = usecsToDate $runEndTimeUsecs
                        $ArchiveRun = $run | Where-Object id -EQ $runid
                      # Capture Archive run details
                        if($ArchiveRun.PSObject.Properties['archivalInfo']){
                        $targetFilterMatched = $false
                        foreach($archiveResult in $Archiverun.archivalInfo.archivalTargetResults){
                                [void]$seenTargets.Add("targetName='$($archiveResult.targetName)' ownershipContext='$($archiveResult.ownershipContext)' status='$($archiveResult.status)'")
                                # Skip this archive result if it doesn't match -ExternalTarget
                                if(!(Test-ExternalTargetFilter $archiveResult)){
                                    continue
                                }
                                # Skip this archive result if it doesn't match -ArchiveRunStatus
                                if(!(Test-ArchiveStatusFilter $archiveResult.status)){
                                    continue
                                }
                                $targetFilterMatched = $true
                                $matchedRowCount++
                                $targetName = $archiveResult.targetName
                                $targetType = $archiveResult.targetType
                                $TargetOwner = $archiveResult.ownershipContext
                                $Archiveexpiry = usecsToDate $archiveResult.expiryTimeUsecs
                                $physicalBytesTransferred = toUnits $archiveResult.stats.physicalBytesTransferred
                                $LogicalBytesTransferred = toUnits $archiveResult.stats.logicalBytesTransferred
                                $AverageTransferRate = Convert-BpsToMbps $archiveResult.stats.avgLogicalTransferRateBps
                                $AverageTransferRate = [math]::Round($AverageTransferRate,3)
                                $ArchiveStatus = $archiveResult.status
                                $ArchiveRun.localBackupInfo.messages
                                if($ArchiveStatus -eq "failed"){
                                $Archiveexpiry = "No Backup to Vault"
                                }
                                if($runstatus -eq "failed"){
                                $backupexpiry = "Job Failed"
                                }
                                $isIncremental = $archiveResult.isIncremental}
                              # Only export if at least one archive result for this run matched the -FortKnox / -CloudArchive / -CloudArchiveDirect filter
                              # (or no filter switches were passed, in which case everything matches)
                              if ($targetFilterMatched){
                              # Export results to csv
                              if ($outfileNamecsv -ne $null){
                                "    {0} ({1}) -> {2} ({3}) {4} {5} {6} {7} {8} $unit {9} $unit {10} $unit {11} $UnitTP {12} {13}" -f $jobname, $runstatus, $objectname, $Objectenvironment, $runStartTime, $backupexpiry, $targetName, $archivestatus, $Archiveexpiry, $physicalBytesTransferred, $LogicalBytesTransferred, $AverageTransferRate, $JobDuration, $ObjectFailureResult
                                """{0}"",""{1}"",""{2}"",""{3}"",""{4}"",""{5}"",""{6}"",""{7}"",""{8}"",""{9}"",""{10}"",""{11}"",""{12}"",""{13}""" -f $jobname, $runstatus, $objectname, $Objectenvironment, $runStartTime, $backupexpiry, $targetName, $archivestatus, $Archiveexpiry, $physicalBytesTransferred, $LogicalBytesTransferred, $AverageTransferRate, $JobDuration, $ObjectFailureResult |Sort-Object "Run Date" -Descending | Out-File -FilePath $outfileNamecsv -Append
                              }
                              # Export results to html - one <tr> per record, appended as the job runs are processed
                              if ($outfileNamehtml -ne $null){
                                $backupStatusClass = Get-HtmlStatusClass $runstatus
                                $archiveStatusClass = Get-HtmlStatusClass $archivestatus
                                $htmlRow = "<tr>" +
                                    "<td>$(ConvertTo-HtmlSafe $jobname)</td>" +
                                    "<td class=""$backupStatusClass"">$(ConvertTo-HtmlSafe $runstatus)</td>" +
                                    "<td>$(ConvertTo-HtmlSafe $objectname)</td>" +
                                    "<td>$(ConvertTo-HtmlSafe $Objectenvironment)</td>" +
                                    "<td>$(ConvertTo-HtmlSafe $runStartTime)</td>" +
                                    "<td>$(ConvertTo-HtmlSafe $backupexpiry)</td>" +
                                    "<td>$(ConvertTo-HtmlSafe $targetName)</td>" +
                                    "<td class=""$archiveStatusClass"">$(ConvertTo-HtmlSafe $archivestatus)</td>" +
                                    "<td>$(ConvertTo-HtmlSafe $Archiveexpiry)</td>" +
                                    "<td>$physicalBytesTransferred $unit</td>" +
                                    "<td>$LogicalBytesTransferred $unit</td>" +
                                    "<td>$AverageTransferRate $UnitTP</td>" +
                                    "<td>$(ConvertTo-HtmlSafe $JobDuration)</td>" +
                                    "<td>$(ConvertTo-HtmlSafe $ObjectFailureResult)</td>" +
                                    "</tr>"
                                $htmlRow | Out-File -FilePath $outfileNamehtml -Append -Encoding utf8
                              }
                              # Create an array to store the data for excel export
                                    $data = @()
                                    $SummaryData = @($objectname,$physicalBytesTransferred)
                              # Format the data and add it to the array
                                $data += [PSCustomObject]@{
                                "Job Name" = $jobname
                                "Run Status" = $runstatus
                                "client Name" = $objectname
                                "Object Type" = $Objectenvironment
                                "Run Date" = $runStartTime
                                "Backup Expiry Date" = $backupexpiry
                                "External Target" = $targetName
                                "Archive Run Status" = $archivestatus
                                "Archive Expiry Date" = $Archiveexpiry
                                "Physical Transferred (MiB)" = $physicalBytesTransferred
                                "Logical Transferred (MiB)" = $LogicalBytesTransferred
                                "Average Throughput (Mbps)" = $AverageTransferRate
                                "Vaulting Process Duration" = $JobDuration
                                "Failure Reason" = $ObjectFailureResult
                                }
                              # Export the data to an Excel file
                              if ($outfileNamexlsx -ne $null){
                                $data | Export-Excel -Path $outfileNamexlsx -AutoSize -Append
                                }
                              }
                        }

                   }
            }
     }
# Close out the html file for this cluster - closing tags for table/body/html
if ($outfileNamehtml -ne $null){
    "</tbody></table></body></html>" | Out-File -FilePath $outfileNamehtml -Append -Encoding utf8
    Write-Host "Html report for Cluster $Clustername written to $outfileNamehtml" -ForegroundColor Green
}
# If nothing matched -ExternalTarget for this cluster, print every distinct target this
# cluster actually returned so we can see the real ownershipContext/targetName values and
# adjust -ExternalTarget or Test-ExternalTargetFilter if targets are being labeled differently here.
if($matchedRowCount -eq 0){
    $statusFilterDesc = if($ArchiveRunStatus.Count -gt 0){ " and -ArchiveRunStatus '$($ArchiveRunStatus -join ',')'" } else { '' }
    Write-Host "No vaulting runs matched -ExternalTarget '$ExternalTarget'$statusFilterDesc for Cluster $Clustername. Targets seen:" -ForegroundColor Yellow
    if($seenTargets.Count -eq 0){
        Write-Host "  (no archive results were found on any run for this cluster)" -ForegroundColor Yellow
    }else{
        foreach($t in $seenTargets){ Write-Host "  $t" -ForegroundColor Yellow }
    }
}
}
Write-Host "Finished writing output for"$Clusternames.count"Clusters with names $Clusternames" -ForegroundColor Green
