#Remove all Variables
#Remove-Variable -Name * -ErrorAction SilentlyContinue

# process commandline arguments
[CmdletBinding()]
param (
    [Parameter()][string]$username = 'DMaaS',  # Your CCS username (username@emaildomain.com)
    [Parameter(Mandatory = $True)][string]$apiKey,  # apiKey    
    [Parameter(Mandatory = $True)][string]$regionId,  # CCS Generic NAS Source Region Id (us-east-1, us-east2, us-west-1, us-west-2)
    [Parameter(Mandatory = $True)][string]$saasConn,  # name of SaaS Connection to associate with gNasical Source
    [Parameter()][array]$gNasFQDNShare = '',  #genericNAS Source FQDN \\IPAddress\c$ or \\FQDN\ShareName
    [Parameter()][array]$gNasDescription,  # gNas Description(Tech Team Share, HR Share, Documents)
    [Parameter()][string]$gNasList = '', # 'C:\FolderPath\gNaslist.txt',  # optional textfile of Generic NAS Sources to protect
    [Parameter()][string]$environment = 'kGenericNas',  # environment type (kgNasical, kVMware, kAWS, kO365, kNetapp, KGenericNas)
    [Parameter()][string]$gNasMode = 'kCifs1', # source type (kHost, kVCenter, kIAMUser, kDomain, kCluster, kCifs1)
    [Parameter(Mandatory = $True)][string]$gNasUserName,  # source Username with appropriate access (.\Admin, .\UserName_User)
    [Parameter()][string]$gNaspassword = '' # source Username's password (SMB password for user account with appropriate access)
    

)

# prompt for smb password if needed
if ($gNasUserName -ne ''){
    if(! $gNaspassword){
        $securePassword = Read-Host -Prompt "Please enter password for $gNasUserName" -AsSecureString
        $cred = New-Object -TypeName System.Net.NetworkCredential
        $cred.SecurePassword =$securePassword
        
       }
    }


# gather list of GenericNas Sources to Register
$gNasSourcesToAdd = @()
foreach($gNas in $gNasFQDNShare){
    $gNasSourcesToAdd += $gNas
}
if ('' -ne $gNasList){
    if(Test-Path -Path $gNasList -PathType Leaf){
        $gNasFQDNShare = Get-Content $gNasList
        foreach($gNas in $gNasFQDNShare){
            $gNasSourcesToAdd += [string]$gNas
        }
    }else{
        Write-Host "gNas Source list $gNasList not found!" -ForegroundColor Yellow
        exit
    }
}

$gNasSourcesToAdd = @($gNasSourcesToAdd | Where-Object {$_ -ne ''})

if($gNasSourcesToAdd.Count -eq 0){
    Write-Host "No gNas Sources specified" -ForegroundColor Yellow
    exit
}

# source the cohesity-api helper code
. $(Join-Path -Path .\ -ChildPath cohesity-api.ps1)
Write-Host "Connecting to CCS"

# authenticate
apiauth -username $username -regionid $regionId


$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"

# test API Connection
Write-host "Testing API Connection...`n"
$headers.Add("apiKey", "$apiKey")
$apiTest = Invoke-RestMethod 'https://helios.cohesity.com/irisservices/api/v1/public/mcm/clusters/info' -Method 'GET' -Headers $headers
if(!$apiTest){
    write-host "Invalid API Key" -ForegroundColor Yellow
    exit
}

# validate CCS Tenant ID
Write-host "Validating Tenant ID...`n"
$headers.Add("accept", "application/json, text/plain, */*")
#$headers.Add('content-type: application/json')
$tenant = Invoke-RestMethod 'https://helios.cohesity.com/irisservices/api/v1/mcm/userInfo' -Method 'GET' -Headers $headers

$tenantId = $tenant.user.profiles.tenantId 
Write-host "Tenant ID: " $tenantId


# validate CCS Region ID
Write-host "`nValidating Region ID..."
$region = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/dms/tenants/regions?tenantId=$tenantId" -Method 'GET' -Headers $headers

foreach($Ids in $region){

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


# register gNasical Server
$headers.Add("regionId", "$regionId")

foreach($gNasSource in $gNasSourcesToAdd){

    Write-Host "Finding Generic Nas Source $gNasSource"
    $gNaspassword = $cred.Password
        #Build the GenericNas Body
           $body = @{
            "environment" = "$environment";
            "connectionId" = [int64]$connectionId;
              "genericnasParams"= @{
                "mode" = "$gNasMode";
                "mountpoint" = "$gNasSource";
                "description" = "$gNasDescription";
                "skipValidation" = $False;          
            "smbMountCredentials" = @{
                "username" = "$gNasUserName";
                "password" = "$gNasPassword"
                  }
            }
            }
            
        
        
 $body = ConvertTo-Json -Compress -Depth 99 $body
 $gNasPassword = $cred.SecurePassword
    if($gNasSource){

        Write-Host "Registering $gNasSource..."
        $response = Invoke-RestMethod 'https://helios.cohesity.com/v2/mcm/data-protect/sources/registrations' -Method 'POST' -Headers $headers -Body $body -ContentType 'application/json'
        $response | out-file -filepath Register_CCS_GenericNasSources-$(Get-Date -f yyyy-MM-dd).txt -Append
        Write-host "$response"
    }

    else{
    Write-Host "Source $gNasSource not found" -ForegroundColor Yellow
    }
    }

    

