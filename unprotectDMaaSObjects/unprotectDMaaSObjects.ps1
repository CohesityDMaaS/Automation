# process commandline arguments
[CmdletBinding()]
param (
    [Parameter()][string]$username = 'DMaaS',
    [Parameter(Mandatory = $True)][string]$region,  # DMaaS region
    [Parameter()][switch]$useApiKey,
    [Parameter()][array]$objectName,
    [Parameter()][string]$objectList,
    [Parameter(Mandatory = $False)][bool]$deleteAllSnapshots = $False  # whether all Snapshots are deleted (default to $False)
)

# gather list from command line params and file
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

$objectNames = @(gatherList -Param $objectName -FilePath $objectList -Name 'objects' -Required $True)
# $jobNames = @(gatherList -Param $jobName -FilePath $jobList -Name 'jobs' -Required $False)


# source the cohesity-api helper code
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)

Write-Host "Connecting to DMaaS"

# authenticate
apiauth -username $username -regionid $region

# outfile
$dateString = (get-date).ToString('yyyy-MM-dd')
$outfileName = "log-unprotectObjects-$dateString.txt"


Write-Host "Finding Protected Objects"

$objects = (api get -v2 data-protect/search/protected-objects).objects | Where-Object name -eq $objectNames
if(!$objects){
    write-host "Object $objectNames not found" -ForegroundColor Yellow
    exit
}

# configure unprotection parameters
$unProtectionParams = @{
    "action" = "UnProtect";
    "objectActionKey" = $objects.environment;
    "unProtectParams" = @{
        "objects" = @( 
            @{
                "id" = $objects.id;
                "deleteAllSnapshots" = $deleteAllSnapshots;
                "forceUnprotect" = $true;
            };
        );
    };
    # "snapshotBackendTypes" = $objects.environment;
}

# unprotect objects
foreach($object in $objects){
    $objectName = $object.name
    Write-Host "Unprotecting $objectName"
    $response = api post -v2 data-protect/protected-objects/actions $unProtectionParams | Tee-Object -FilePath ./$outfileName -Append
}

"`nOutput saved to $outfilename`n"