#./DMaaS_Source_Refresh.ps1 -region us-east-2 -sourceID 772,3306 

# process commandline arguments
[CmdletBinding()]
param (
    [Parameter()][string]$username = 'DMaaS',
    [Parameter(Mandatory = $True)][string]$region,  # DMaaS region
    [Parameter(Mandatory = $True)][string]$sourceID  # ID of registered DMaaS Source
)

# source the cohesity-api helper code
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)

# authenticate
apiauth -username $username -regionid $region

#Connect-CohesityCluster -Server helios.cohesity.com -RegionId $region -Username $username

#$source = Get-CohesityProtectionSource | Where-Object {$_.protectionSource.id -eq $sourceID}
$source = api get protectionSources | Where-Object {$_.protectionSource.id -eq $sourceID}
if (!$source){
    Write-Host "DMaaS Source $sourceID not found" -ForegroundColor Yellow
    exit
}

if($source.protectionSource.id -gt 0){
    $source_id = $source.protectionSource.id
    #$response = Update-CohesityProtectionSource -Id $source_id
    $response = api post -v1 protectionSources/refresh/$source_id
    Write-Host "`nSuccessfully Refreshed: $source_id`n"
    $response
}else{
    Write-Host "No Sources Refreshed."
}




