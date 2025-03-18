######################################################################################################################################################################################################################
#This Script ## the following tasks:
#The sole purpose is to collect data related to backup and archive operations for multiple clusters and writing this information to separate CSV and xlsx files for each cluster. The records are 
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
#It formats the extracted data and appends it to the output file as a CSV record as well as excel-Optionally you can comment out either export(File creation steps and export steps) .
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
    [Parameter(mandatory = 'true')][string]$username = '',
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
    [Parameter()][ValidateSet('MiB','GiB')][string]$unit = 'MiB'
)

$conversion = @{'Kib' = 1024; 'MiB' = 1024 * 1024; 'GiB' = 1024 * 1024 * 1024; 'TiB' = 1024 * 1024 * 1024 * 1024}
function toUnits($val){
    return "{0:n0}" -f ($val/($conversion[$unit]))
}

function Convert-BpsToMbps {
    param (
        [double]$bps
    )
    $UnitTP = 'Mbps'
    $mbps = $bps / 1e6  # 1 Mbps = 1,000,000 bps
    return $mbps
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

# Create the csv output report headings- You can comment out the below lines if you prefer to use the Excel Option
if ($outfileNamecsv -ne $null){
"Job Name,Backup Run Status,client Name,Object Type,Run Date,Backup Expiry Date,External Target,Archive Run Status,Archive Expiry Date,Physical Transferred ($unit),Logical Transferred ($unit),Average Throughput ($unitTP),Vaulting Process Duration,Failure Reason"  | Out-File -FilePath $outfileNamecsv -Encoding utf8
}
$nowUsecs = timeAgo 1 second

# Get list of jobs for the Cluster
$thisCluster = heliosCluster $clusterName
Write-Host "Fetching list of Backup Jobs for Cluster $Clustername" -ForegroundColor Green
$jobs = api get -v2 "data-protect/protection-groups?includeTenants=true&isActive=true&isDeleted=false&isPaused=false" 

Write-Host "Processing job to extract backup and archive details for Cluster $Clustername" -ForegroundColor Green
foreach ($job in $jobs.protectionGroups | Sort-Object -Property name){
    $endUsecs = dateToUsecs (Get-Date)            
            $runs = api get -v2 "data-protect/protection-groups/$($job.id)/runs?numRuns=$numRuns&endTimeUsecs=$endUsecs&includeTenants=true&includeObjectDetails=true"
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
                        $ObjectRunStatus = $Object.localSnapshotInfo.snapshotInfo.status.Split("k")[-1]
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
                        foreach($archiveResult in $Archiverun.archivalInfo.archivalTargetResults){
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
                              # Export results to csv
                              if ($outfileNamecsv -ne $null){
                                "    {0} ({1}) -> {2} ({3}) {4} {5} {6} {7} {8} $unit {9} $unit {10} $unit {11} $UnitTP {12} {13}" -f $jobname, $runstatus, $objectname, $Objectenvironment, $runStartTime, $backupexpiry, $targetName, $archivestatus, $Archiveexpiry, $physicalBytesTransferred, $LogicalBytesTransferred, $AverageTransferRate, $JobDuration, $ObjectFailureResult
                                """{0}"",""{1}"",""{2}"",""{3}"",""{4}"",""{5}"",""{6}"",""{7}"",""{8}"",""{9}"",""{10}"",""{11}"",""{12}"",""{13}""" -f $jobname, $runstatus, $objectname, $Objectenvironment, $runStartTime, $backupexpiry, $targetName, $archivestatus, $Archiveexpiry, $physicalBytesTransferred, $LogicalBytesTransferred, $AverageTransferRate, $JobDuration, $ObjectFailureResult |Sort-Object "Run Date" -Descending | Out-File -FilePath $outfileNamecsv -Append
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


Write-Host "Finished writing output for"$Clusternames.count"Clusters with names $Clusternames" -ForegroundColor Green

