#./DMaaS_Source_Refresh.ps1 -region us-east-2 -sourceID 772,3306 

### process commandline arguments
[CmdletBinding()]
param (
    # [Parameter()][string]$vip = 'helios.cohesity.com',
    [Parameter()][string]$username = 'DMaaS',
    [Parameter(Mandatory = $True)][string]$region,  # DMaaS region
    [Parameter()][switch]$useApiKey,
    [Parameter()][string]$password,
    # [Parameter()][switch]$mcm,
    # [Parameter()][string]$clusterName = $null,
    [Parameter(Mandatory = $True)][string]$sourceName,
    # [Parameter(Mandatory = $True)][string]$jobName,
    [Parameter()][array]$vmName,
    [Parameter()][string]$vmList,
    [Parameter()][ValidateSet('kNative', 'kSnapshotManager')][string]$cohesityProtectionType = 'kNative',
    [Parameter()][ValidateSet('kNative', 'kSnapshotManager')][string]$awsProtectionType = 'kSnapshotManager',
    [Parameter()][string]$startTime = '20:00',
    [Parameter()][string]$timeZone = 'America/New_York',
    [Parameter()][int]$incrementalSlaMinutes = 60,
    [Parameter()][int]$fullSlaMinutes = 120,
    # [Parameter()][string]$storageDomainName = 'DefaultStorageDomain',
    [Parameter()][string]$cohesityPolicyName,
    [Parameter()][string]$awsPolicyName,
    # [Parameter()][switch]$paused,
    [Parameter()][ValidateSet('kBackupHDD', 'kBackupSSD')][string]$qosPolicy = 'kBackupSSD'
)

# source the cohesity-api helper code
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)

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

function gatherList($Param=$null, $FilePath=$null, $Required=$True, $Name='items'){
    $items = @()
    if($Param){
        $Param | ForEach-Object {$items += $_}
    }
    if($FilePath){
        if(Test-Path -Path $FilePath -PathType Leaf){
            Get-Content $FilePath | ForEach-Object {$items += [string]$_}
        }else{
            Write-Host "Text file $FilePath not found!" -ForegroundColor Yellow
            exit
        }
    }
    if($Required -eq $True -and $items.Count -eq 0){
        Write-Host "No $Name specified" -ForegroundColor Yellow
        exit
    }
    return ($items | Sort-Object -Unique)
}

$vmNames = @(gatherList -Param $vmName -FilePath $vmList -Name 'vms' -Required $True)

# authenticate
apiauth -username $username -regionid $region


# select helios/mcm managed cluster
# if($USING_HELIOS){
#     if($clusterName){
#         heliosCluster $clusterName
#     }else{
#         write-host "Please provide -clusterName when connecting through helios" -ForegroundColor Yellow
#         exit 1
#     }
# }

# $awsParamName = @{
#     'kAgent' = 'agentProtectionTypeParams'; 
#     'kNative'= 'nativeProtectionTypeParams';
#     'kSnapshotManager' = 'snapshotManagerProtectionTypeParams'
# }

# get registered AWS source
Write-Host "`nGathering AWS protection source info..."
$source = api get "protectionSources?environments=kAWS" | Where-Object {$_.protectionSource.name -eq $sourceName}
if(!$source){
    Write-Host "AWS protection source '$sourceName' not found" -ForegroundColor Yellow
    exit
}

$sourceId = $source.protectionSource.id
$sourceName = $source.protectionSource.name

# get the protectionJob
# Write-Host "`nLooking for existing protection job..."
# $job = (api get -v2 "data-protect/protection-groups?environments=kAWS").protectionGroups | Where-Object {$_.name -eq $jobName}

# if(! $job){

#     $newJob = $True

#     $awsParam = $awsParamName[$protectionType]

#     if($paused){
#         $isPaused = $True
#     }else{
#         $isPaused = $false
#     }

# parse startTime
$hour, $minute = $startTime.split(':')
$tempInt = ''
if(! (($hour -and $minute) -or ([int]::TryParse($hour,[ref]$tempInt) -and [int]::TryParse($minute,[ref]$tempInt)))){
    Write-Host "Please provide a valid start time" -ForegroundColor Yellow
    exit
}



# get storageDomain
# $viewBoxes = api get viewBoxes
# if($viewBoxes -is [array]){
#         $viewBox = $viewBoxes | Where-Object { $_.name -ieq $storageDomainName }
#         if (!$viewBox) { 
#             write-host "Storage domain $storageDomainName not Found" -ForegroundColor Yellow
#             exit
#         }
# }else{
#     $viewBox = $viewBoxes[0]
# }

$backupGroup = @{
    "policyConfig" = @{
    # "name" = $jobName;
        "policies" = @();  
    };  
    # "storageDomainId" = $viewBox.id;
    # "description" = "";
    "startTime" = @{
        "hour"     = [int]$hour;
        "minute"   = [int]$minute;
        "timeZone" = $timeZone
    };
    "priority" = "kMedium";
    # "alertPolicy" = @{
    #     "backupRunStatus" = @(
    #         "kFailure"
    #     );
    #     "alertTargets" = @()
    # };
    "sla" = @(
        @{
            "backupRunType" = "kFull";
            "slaMinutes"    = $fullSlaMinutes
        };
        @{
            "backupRunType" = "kIncremental";
            "slaMinutes"    = $incrementalSlaMinutes
        }
    );
    "qosPolicy" = $qosPolicy;
    "abortInBlackouts" = $false;
    # "isActive" = $True;
    # "isPaused" = $isPaused;
    "objects" = @{
        "environment" = "kAWS";
        # "permissions" = @();
        # "missingEntities" = $null;
        "awsParams" = @{
            "protectionType" = $awsProtectionType;
            "snapshotManagerProtectionTypeParams" = @{
                "createAmi" = $false;
                "objects" = @{
                    #"sourceId" = $sourceId;
                    "volumeExclusionParams" = $null;
                    "excludeObjectIds" = @()
                };
                "excludeVmTagIds" = @();
            };
            "nativeProtectionTypeParams" = @{
                "createAmi" = $false;
                "objects" = @{
                    #"sourceId" = $sourceId;
                    "volumeExclusionParams" = $null;
                    "excludeObjectIds" = @()
                };
                "excludeVmTagIds" = @()
                # "indexingPolicy" = @{
                #     "enableIndexing" = $true;
                #     "includePaths" = @(
                #         "/"
                #     );
                #     "excludePaths" = @(
                #         '/$Recycle.Bin';
                #         "/Windows";
                #         "/Program Files";
                #         "/Program Files (x86)";
                #         "/ProgramData";
                #         "/System Volume Information";
                #         "/Users/*/AppData";
                #         "/Recovery";
                #         "/var";
                #         "/usr";
                #         "/sys";
                #         "/proc";
                #         "/lib";
                #         "/grub";
                #         "/grub2";
                #         "/opt";
                #         "/splunk"
                #    )
                # }
            }
        }

    }
    
}

# ????????????????????
    # $newJob = $false
    # $awsParam = $awsParamName[$backupGroup.awsParams.protectionType]
    # if($backupGroup.awsParams.$awsParam.sourceId -ne $sourceId){
    #     # Write-Host "Protection job '$jobName' uses a different registered AWS protection source" -ForegroundColor Yellow
    #     Write-Host "Protection group uses a different registered AWS protection source" -ForegroundColor Yellow
    #     exit
    # }
# ????????????????????

# if($newJob -eq $True){
#     # Write-Host "`nCreating protection job '$jobName'...`n"
#     Write-Host "`nCreating protection group...`n"
# }else{
#     # Write-Host "`nUpdating protection job '$jobName'...`n"
#     Write-Host "`nUpdating protection group...`n"
# }

if(!$cohesityPolicyName -AND !$awsPolicyName){
    Write-Host "At least one Policy Name (-cohesityPolicyName and/or -awsPolicyName) is required to create a new backup group" -ForegroundColor Yellow
    exit
}

$cohesityPolicy = (api get -mcmv2 data-protect/policies?types=DMaaSPolicy).policies | Where-Object name -eq $cohesityPolicyName
if(!$cohesityPolicy){
    Write-Host "Cohesity Policy $cohesityPolicyName not present" -ForegroundColor Yellow
    $cohesityPolicyName = ""
    $cohesityPolicy = ""
}else{
    $backupGroup.policyConfig.policies = @($backupGroup.policyConfig.policies + @{"id" = $cohesityPolicy.id; "protectionType" = $cohesityProtectionType})
}

# if(!$awsPolicyName){
#     Write-Host "-policyName required to create new protection job" -ForegroundColor Yellow
#     exit
# }

$awsPolicy = (api get -mcmv2 data-protect/policies?types=DMaaSPolicy).policies | Where-Object name -eq $awsPolicyName
if(!$awsPolicy){
    Write-Host "AWS Policy $awsPolicyName not present" -ForegroundColor Yellow
    $awsPolicyName = ""
    $awsPolicy = ""
}else{
    $backupGroup.policyConfig.policies = @($backupGroup.policyConfig.policies + @{"id" = $awsPolicy.id; "protectionType" = $awsProtectionType})
}

foreach($vm in $vmnames){
    $vmid = getObjectId $vm $source
    if($vmid){
        Write-Host "    Protecting '$vm'"
        $existingObject = $backupGroup.objects.awsParams.snapshotManagerProtectionTypeParams.objects | Where-Object {$_.id -eq $vmid}
        $existingObject = $backupGroup.objects.awsParams.nativeProtectionTypeParams.objects | Where-Object {$_.id -eq $vmid}
        if(! $existingObject){
            $backupGroup.objects.awsParams.snapshotManagerProtectionTypeParams.objects = @($backupGroup.objects.awsParams.snapshotManagerProtectionTypeParams.objects + @{"id" = $vmid})
            $backupGroup.objects.awsParams.nativeProtectionTypeParams.objects = @($backupGroup.objects.awsParams.nativeProtectionTypeParams.objects + @{"id" = $vmid})
        }
    }else{
        Write-Host "    VM '$vm' not found" -ForegroundColor Yellow
    }
}

# if($newJob -eq $True){
#     $null = api post -v2 "data-protect/protected-objects" $backupGroup
# }else{
#     $null = api put "data-protect/protection-groups/$($job.id)" $job -v2
# }
# Write-Host ""

$response = api post -v2 "data-protect/protected-objects" $backupGroup

Write-Host "$response"

