# process commandline arguments
[CmdletBinding()]
param (
    [Parameter()][string]$username = 'DMaaS',
    [Parameter(Mandatory = $True)][string]$region,  # DMaaS region
    [Parameter(Mandatory = $True)][string]$policyName = '',  # protection policy name
    [Parameter(Mandatory = $True)][string]$sourceName,  # name of registered VMware source
    [Parameter(Mandatory = $True)][bool]$autoProtected,  # whether VMware objects are autoProtected
    [Parameter()][bool]$appConsistent = $false,  # optional whether VMware objects are quiesced (Default is false)
    [Parameter()][bool]$skipPhysicalRDMDisks = $false,  # optional whether to skip backing up Physical RDM Disks (Default is false)
    [Parameter()][array]$vmNames,  # optional names of VMs protect
    [Parameter()][string]$vmList = '',  # optional textfile of VMs to protect
    #[Parameter()][ValidateSet('All', 'CohesitySnapshot', 'AWSSnapshot')][string]$protectionType = 'CohesitySnapshot',
    [Parameter()][string]$startTime = '20:00',  # e.g. 23:30 for 11:30 PM
    [Parameter()][string]$timeZone = 'America/New_York', # e.g. 'America/New_York'
    [Parameter()][int]$incrementalSlaMinutes = 60,  # incremental SLA minutes
    [Parameter()][int]$fullSlaMinutes = 120  # full SLA minutes
)

# gather list of VMs to protect
$vmNamesToAdd = @()
foreach($VM in $vmNames){
    $vmNamesToAdd += $VM
}
if ('' -ne $vmList){
    if(Test-Path -Path $vmList -PathType Leaf){
        $vmNames = Get-Content $vmList
        foreach($VM in $vmNames){
            $vmNamesToAdd += [string]$VM
        }
    }else{
        Write-Host "VM list $vmList not found!" -ForegroundColor Yellow
        exit
    }
}

$vmNamesToAdd = @($vmNamesToAdd | Where-Object {$_ -ne ''})

if($vmNamesToAdd.Count -eq 0){
    Write-Host "No VMs specified" -ForegroundColor Yellow
    exit
}

# parse startTime
$hour, $minute = $startTime.split(':')
$tempInt = ''
if(! (($hour -and $minute) -or ([int]::TryParse($hour,[ref]$tempInt) -and [int]::TryParse($minute,[ref]$tempInt)))){
    Write-Host "Please provide a valid start time" -ForegroundColor Yellow
    exit
}

function getObjectId($objectName, $source){
    $global:_object_id = $null

    function get_nodes($obj){
        if($obj.protectionSource.name -eq $objectName){
            $global:_object_id = $obj.protectionSource.id
            break
        }
        if($obj.PSObject.Properties['nodes']){
            foreach($node in $obj.nodes){
                if($null -eq $global:_object_id){
                    get_nodes $node
                }
            }
        }
    }
    get_nodes $source
    return $global:_object_id
}

# source the cohesity-api helper code
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)

Write-Host "Connecting to DMaaS"

# authenticate
apiauth -username $username -regionid $region

Write-Host "Finding protection policy"

$policy = (api get -mcmv2 data-protect/policies?types=DMaaSPolicy).policies | Where-Object name -eq $policyName
if(!$policy){
    write-host "Policy $policyName not found" -ForegroundColor Yellow
    exit
}

Write-host "Finding registered VMware source"
# find AWS source
$source = (api get protectionSources?environments=kVMware) | Where-Object {$_.protectionSource.name -eq $sourceName}
if(!$source){
    Write-Host "VMware Source $sourceName not found" -ForegroundColor Yellow
    exit
}

# configure protection parameters
$protectionParams = @{
    "policyId" = $policy.id;
    "startTime"        = @{
        "hour"     = [int64]$hour;
        "minute"   = [int64]$minute;
        "timeZone" = $timeZone
    };
    "priority" = "kMedium";
    "sla"              = @(
        @{
            "backupRunType" = "kFull";
            "slaMinutes"    = $fullSlaMinutes
        };
        @{
            "backupRunType" = "kIncremental";
            "slaMinutes"    = $incrementalSlaMinutes
        }
    );
    "qosPolicy" = "kBackupSSD";
    "abortInBlackouts" = $false;
    "objects" = @(
        @{
            "environment" = "kVMware";
            "vmwareParams" = @{
                "objects" = @();
                "excludeVmTagIds" = @();
                "appConsistentSnapshot" = $appConsistent;
                "fallbackToCrashConsistentSnapshot" = $true;
                "skipPhysicalRDMDisks" = $skipPhysicalRDMDisks;
                "globalExcludeDisks" = @();
                # "indexingPolicy" = @{
                #     "enableIndexing" = $false;
                #     "includePaths" = @();
                #     "excludePaths" = @()
                # };           
            }
        }
    )
}


# find VMs
foreach($vmName in $vmNamesToAdd){

    Write-Host "Finding VM $vmName"
    $vmId = getObjectId $vmName $source

    if($vmId){
        $protectionParams.objects.vmwareParams.objects = @(
            @{
                "id" = $vmId;
                "isAutoprotected" = $autoProtected;
                "volumeExclusionParams" = $null;
                "excludeObjectIds" = @()
            }
        )
        Write-Host "Protecting $vmName"
        $response = api post -v2 data-protect/protected-objects $protectionParams
    }else{
        Write-Host "VM $vmName not found" -ForegroundColor Yellow
    }
}