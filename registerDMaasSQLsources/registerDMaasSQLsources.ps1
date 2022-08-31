
# process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apiKey,  # apiKey
    [Parameter(Mandatory = $True)][string]$regionId,  # DMaaS SQL Source Region Id
    [Parameter(Mandatory = $True)][string]$saasConn,  # name of SaaS Connection to associate with SQL Source
    [Parameter()][array]$sqlFQDN,  # SQL FQDN
    [Parameter()][string]$sqlList = ''  # optional textfile of SQL Servers to protect

)

# gather list of SQL Sources to Register
$SQLServersToAdd = @()
foreach($SQL in $sqlFQDN){
    $SQLServersToAdd += $SQL
}
if ('' -ne $sqlList){
    if(Test-Path -Path $sqlList -PathType Leaf){
        $sqlFQDN = Get-Content $sqlList
        foreach($SQL in $sqlFQDN){
            $SQLServersToAdd += [string]$SQL
        }
    }else{
        Write-Host "SQL Server list $sqlList not found!" -ForegroundColor Yellow
        exit
    }
}

$SQLServersToAdd = @($SQLServersToAdd | Where-Object {$_ -ne ''})

if($SQLServersToAdd.Count -eq 0){
    Write-Host "No SQL Servers specified" -ForegroundColor Yellow
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
 
$saasList = for ( $i = 0; $i -lt $max; $i++)
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


# register SQL Server
$headers.Add("regionId", "$regionId")

foreach($SQLServer in $SQLServersToAdd){

    Write-Host "Finding VM $SQLServer"
    
    $body = "{
        `n    `"environment`": `"kPhysical`",
        `n    `"connectionId`": $connectionId,
        `n    `"physicalParams`": {
        `n        `"endpoint`": `"$SQLServer`",
        `n        `"hostType`": `"kWindows`",
        `n        `"physicalType`": `"kHost`",
        `n        `"applications`": [
        `n            `"kSQL`"
        `n        ]
        `n    }
        `n}"

    if($SQLServer){
    Write-Host "Registering $SQLServer..."
    $response = Invoke-RestMethod 'https://helios.cohesity.com/v2/mcm/data-protect/sources/registrations' -Method 'POST' -Headers $headers -Body $body -ContentType 'application/json' 
    $response | out-file -filepath DMaaSSQLLog-(get-date).txt -Append

    Write-host "$response"
    }
    }else{
        Write-Host "SQL Server $SQLServer not found" -ForegroundColor Yellow
}
