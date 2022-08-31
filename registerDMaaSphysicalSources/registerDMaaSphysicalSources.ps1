
# process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apiKey,  # apiKey
    [Parameter(Mandatory = $True)][string]$regionId,  # DMaaS SQL Source Region Id
    [Parameter(Mandatory = $True)][string]$saasConn,  # name of SaaS Connection to associate with Physical Source
    [Parameter()][array]$physFQDN,  # physical Source FQDN
    [Parameter()][string]$physList = '',  # optional textfile of Physical Servers to protect
    [Parameter(Mandatory = $True)][string]$hostType,  # physical source OS (kWindows, kLinux)
    [Parameter(Mandatory = $True)][string]$environment,  # environment type (kPhysical, kVMware, kAWS, kO365, kNetapp)
    [Parameter(Mandatory = $True)][string]$physType  # source type (kHost, kVCenter, kIAMUser, kDomain, kCluster)

)

# outfile
$dateString = (get-date).ToString('yyyy-MM-dd')
$outfileName = "log-registerDMaasPhysical-$dateString.txt"

# gather list of SQL Sources to Register
$physServersToAdd = @()
foreach($phys in $physFQDN){
    $physServersToAdd += $phys
}
if ('' -ne $physList){
    if(Test-Path -Path $physList -PathType Leaf){
        $physFQDN = Get-Content $physList
        foreach($phys in $physFQDN){
            $physServersToAdd += [string]$phys
        }
    }else{
        Write-Host "Physical Server list $physList not found!" -ForegroundColor Yellow
        exit
    }
}

$physServersToAdd = @($physServersToAdd | Where-Object {$_ -ne ''})

if($physServersToAdd.Count -eq 0){
    Write-Host "No Physical Servers specified" -ForegroundColor Yellow
    exit
}

$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"

# test API Connection
Write-host "Testing API Connection...`n"
$headers.Add("apiKey", "$apiKey")
$apiTest = Invoke-RestMethod 'https://helios.cohesity.com/irisservices/api/v1/public/mcm/clusters/info' -Method 'GET' -Headers $headers 

if(!$apiTest){
    write-host "Invalid API Key" -ForegroundColor Yellow
    exit
}

# validate DMaaS Tenant ID
Write-host "Validating Tenant ID...`n"
$headers.Add("accept", "application/json, text/plain, */*")
#$headers.Add('content-type: application/json')
$tenant = Invoke-RestMethod 'https://helios.cohesity.com/irisservices/api/v1/mcm/userInfo' -Method 'GET' -Headers $headers

$tenantId = $tenant.user.profiles.tenantId 
Write-host "Tenant ID: " $tenantId


# validate DMaaS Region ID
Write-host "`nValidating Region ID..."
$region = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/dms/tenants/regions?tenantId=$tenantId" -Method 'GET' -Headers $headers

foreach($regionIds in $region){

    $regionIds = $region.tenantRegionInfoList.regionId

    $compareRegion = Compare-Object -IncludeEqual -ReferenceObject $regionIds -DifferenceObject $regionId -ExcludeDifferent

    if(!$compareRegion){
        write-host "There are no matching Region Ids asssociated with the confirmed Tenant ID." -ForegroundColor Yellow
        exit
    }

}

# determine SaaS Connector ID
Write-host "`nDetermining SaaS Connection ID..."
$connectors = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/rigelmgmt/rigel-groups?tenantId=$tenantId&maxRecordLimit=1000" -Method 'GET' -Headers $headers 

$names = $connectors.rigelGroups.groupName
$connections = $connectors.rigelGroups.groupId

$saasNames = @($names)
$saasIds = @($connections)


[int]$max = $saasNames.Count
if ([int]$saasIds.count -gt [int]$saasNames.count) { $max = $saasIds.Count; }
 
$saasList = for ($i = 0; $i -lt $max; $i++)
{
    Write-Verbose "$($saasNames[$i]),$($saasIds[$i])"
    [PSCustomObject]@{
        SaaSConnectionName = $saasNames[$i]
        SaaSConnectionID = $saasIds[$i]
 
    }
}


$saasId = $saasList | select-string -pattern $saasConn 
 
$saasId = "$saasId".split(";")
$saasId = $saasId[1]
$saasId = "$saasId".split("=")
$saasId = $saasId[1]
$saasId = "$saasId".split("}")
$connectionId = $saasId[0]


Write-host "`nSaaS Connection ID: $connectionId"


# register Physical Server
$headers.Add("regionId", "$regionId")

foreach($physServer in $physServersToAdd){

    Write-Host "Finding Physical Server $physServer"
    
    # $body = @{
    #     "environment" = $environment;
    #     "connectionId" = $connectionId;
    #     "physicalParams" = @{
    #         "endpoint" = $physServer;
    #         "hostType" = $hostType;
    #         "physicalType" = $physType
    #     };
    # }

    # $body | ConvertTo-Json

    $body = "{
        `n    `"environment`": `"$environment`",
        `n    `"connectionId`": $connectionId,
        `n    `"physicalParams`": {
        `n        `"endpoint`": `"$physFQDN`",
        `n        `"hostType`": `"$hostType`",
        `n        `"physicalType`": `"$physType`"
        `n    }
        `n}"

    if($physServer){

        Write-Host "Registering $physServer..."
        $response = Invoke-RestMethod 'https://helios.cohesity.com/v2/mcm/data-protect/sources/registrations' -Method 'POST' -Headers $headers -Body $body -ContentType 'application/json' 
        $response | out-file -filepath ./$outfileName -Append
       
        Write-host "$response"
    }

    else{
    Write-Host "Server $physServer not found" -ForegroundColor Yellow
    }
}