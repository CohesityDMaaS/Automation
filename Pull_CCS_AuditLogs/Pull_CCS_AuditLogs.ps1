

# ./Pull_CCS_AuditLogs.ps1 -apiKey #### -regionAll

# install PowerShell, if on macOS: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-macos?view=powershell-7.2
# upgrade PowerShell Module to current revision of 7.2.4: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.2#msi

# process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apiKey,  # apiKey generated in CCS UI
    [Parameter()][array]$regionId,  # CCS region ID(s) (comma separated)
    [Parameter()][switch]$regionAll,  # switch to indicate that ALL CCS Regions will be pulled for Audit Report (recommended)
        # it is MANDATORY that you use one of either regionId or regionAll
    [Parameter()][int]$days = 1,  # how many days of logs to pull
    [Parameter()][string]$uri  # how many days of logs to pull

)

# set static variables
$dateString = (get-date).ToString('yyyy-MM-dd')
$dateTime = Get-Date -Format "MM/dd/yyyy HH:mm"
$outfileName = "$PSScriptRoot\log-Pull_CCS_AuditLogs-$dateString.txt"

# Get the End Date
[long]$endtimeusecs = (([datetime]::Now)-(Get-Date -Date '1/1/1970')).TotalMilliseconds * 1000

# Get the Start Date (1 day ago)
[long]$starttimeusecs = ((([datetime]::Now).AddDays(-[int]$days))-(Get-Date -Date '1/1/1970')).TotalMilliseconds * 1000


Write-Output "`n#---------------------------------------------------------------------------------------------------------------#`n" | Out-File -FilePath $outfileName -Append

# ensure the environment meets the PowerShell Module requirements of 5.1 or above 
write-host "`nValidating PowerShell Version...`n"
Write-Output "`n$dateTime    INFO    Validating PowerShell Version...`n" | Out-File -FilePath $outfileName -Append

$version = $PSVersionTable.PSVersion
if($version.major -lt 5.1){
    write-host "Please upgrade the PowerShell Module to the current revision of 7.2.4 by downloading from the Microsoft site: `nhttps://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.2#msi`n" -ForegroundColor Yellow
    Write-Output "$dateTime    WARN    Please upgrade the PowerShell Module to the current revision of 7.2.4 by downloading from the Microsoft site: `nhttps://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.2#msi`n" | Out-File -FilePath $outfileName -Append
}
else {
    write-host "PowerShell Module is up to date.`n" -ForegroundColor Green
    Write-Output "$dateTime    INFO    PowerShell Module is up to date.`n" | Out-File -FilePath $outfileName -Append
}


# create Audit_Logs folder
Write-host "`nCreating Audit_Logs subfolder...`n" 
Write-Output "`n$dateTime    INFO    Creating Audit_Logs subfolder...`n" | Out-File -FilePath $outfileName -Append 

$auditFolder = "Audit_Logs"

    if (Test-Path $PSScriptRoot\$auditFolder) {
    
        Write-Host "Audit_Logs Folder already exists.`n" -ForegroundColor Green
        Write-Output "$dateTime    INFO    Audit_Logs Folder already exists.`n" | Out-File -FilePath $outfileName -Append 
    }
    else {
    
        #PowerShell Create directory if not exists
        New-Item $auditFolder -ItemType Directory
        Write-Host "Audit_Logs Folder Created SUCCESSFULLY!`n" -ForegroundColor Green
        Write-Output "$dateTime    INFO    Audit_Logs Folder Created SUCCESSFULLY!`n" | Out-File -FilePath $outfileName -Append 
    }

    $auditLogs = "$PSScriptRoot\$auditFolder"


# test API Connection
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"

Write-host "`nTesting API Connection...`n" 
Write-Output "`n$dateTime    INFO    Testing API Connection...`n" | Out-File -FilePath $outfileName -Append 
$headers.Add("apiKey", "$apiKey")
$apiTest = Invoke-RestMethod 'https://helios.cohesity.com/irisservices/api/v1/public/mcm/clusters/info' -Method 'GET' -Headers $headers 

if(!$apiTest){
    write-host "Invalid API Key!" -ForegroundColor Red 
    write-output "$dateTime    FAIL    Invalid API Key!" | Out-File -FilePath $outfileName -Append 
    exit
}else{
    Write-Host "Connection with apiKey SUCCESSFUL!`n" -ForegroundColor Green 
    write-output "$dateTime    INFO    Connection with apiKey SUCCESSFUL!`n" | Out-File -FilePath $outfileName -Append 
    #write-output $apiTest | Out-File -FilePath $outfileName -Append 
}


# validate CCS Tenant ID
Write-host "`nValidating Tenant ID...`n"  
write-output "`n$dateTime    INFO    Validating Tenant ID...`n" | Out-File -FilePath $outfileName -Append 
$headers.Add("accept", "application/json, text/plain, */*")
#$headers.Add('content-type: application/json')
$tenant = Invoke-RestMethod 'https://helios.cohesity.com/irisservices/api/v1/mcm/userInfo' -Method 'GET' -Headers $headers

$tenantId = $tenant.user.profiles.tenantId 

if(!$tenantId){
    write-host "No CCS Tenant ID found!`n" -ForegroundColor Yellow
    write-output "$dateTime    WARN    No CCS Tenant ID found!`n" | out-file -filepath $outfileName -Append
}
else{
    Write-host "Tenant ID: $tenantId`n" -ForegroundColor Green 
    write-output "$dateTime    INFO    Tenant ID: $tenantId`n" | Out-File -FilePath $outfileName -Append 
}


# validate CCS Region ID
Write-host "`nValidating CCS Region ID...`n" 
write-output "`n$dateTime    INFO    Validating CCS Region ID...`n" | Out-File -FilePath $outfileName -Append 
$region = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/dms/tenants/regions?tenantId=$tenantId" -Method 'GET' -Headers $headers
$regions = $region.tenantRegionInfoList.regionId

if($regionAll -eq $true){
    $regionId = "ap-southeast-1", "us-west-1", "ap-south-1", "us-east-1", "us-east-2", "us-west-2", "ca-central-1", "ap-southeast-2", "eu-central-1", "eu-west-2", "azure-centralus"

    $compareRegion = Compare-Object -IncludeEqual -ReferenceObject $regions -DifferenceObject $regionId -ExcludeDifferent

    $verRegion = $compareRegion.InputObject | where-object{$compareRegion.SideIndicator -eq "=="}
    # $invRegion = $compareRegion.InputObject | where-object{$compareRegion.SideIndicator -ne "=="}

    # if($invRegion){
    #     write-host "`nThe CCS Region Id $invRegion is NOT asssociated with the specified Tenant ID!`n" -ForegroundColor Yellow 
    #     write-output "`n$dateTime    WARN    The CCS Region Id $invRegion is NOT asssociated with the specified Tenant ID!`n" | Out-File -FilePath $outfileName -Append 
    # }
    
    $regionIds = ($verRegion -join ",")

    if($regionIds){
        Write-Host "CCS Region ID Verified: $regionIds`n" -ForegroundColor Green
        write-output "$dateTime    INFO    CCS Region ID Verified: $regionIds`n" | Out-File -FilePath $outfileName -Append 
    }
    else{
        write-host "The CCS Region Id $regionIds is NOT asssociated with the specified Tenant ID!`n" -ForegroundColor Yellow 
        write-output "$dateTime    WARN    The CCS Region Id $regionIds is NOT asssociated with the specified Tenant ID!`n" | Out-File -FilePath $outfileName -Append 
    }  
}

elseif($regionId){
    $compareRegion = Compare-Object -IncludeEqual -ReferenceObject $regions -DifferenceObject $regionId -ExcludeDifferent

    $verRegion = $compareRegion.InputObject | where-object{$compareRegion.SideIndicator -eq "=="}
    # $invRegion = $compareRegion.InputObject | where-object{$compareRegion.SideIndicator -ne "=="}

    # if($invRegion){
    #     write-host "`nThe CCS Region Id $invRegion is NOT asssociated with the specified Tenant ID!`n" -ForegroundColor Yellow 
    #     write-output "`n$dateTime    WARN    The CCS Region Id $invRegion is NOT asssociated with the specified Tenant ID!`n" | Out-File -FilePath $outfileName -Append 
    # }
    
    $regionIds = ($verRegion -join ",")

    if($regionIds){
        Write-Host "CCS Region ID Verified: $regionIds`n" -ForegroundColor Green
        write-output "$dateTime    INFO    CCS Region ID Verified: $regionIds`n" | Out-File -FilePath $outfileName -Append 
    }
    else{
        write-host "The CCS Region Id $regionIds is NOT asssociated with the specified Tenant ID!`n" -ForegroundColor Yellow 
        write-output "$dateTime    WARN    The CCS Region Id $regionIds is NOT asssociated with the specified Tenant ID!`n" | Out-File -FilePath $outfileName -Append 
    }  
}


# pulling CCS Audit Logs and saving to delimited csv format
if($days -gt 1){
    Write-Host "`nPulling CCS Audit Logs from $days days ago...`n" 
    write-output "`n$dateTime    INFO    Pulling CCS Audit Logs from $days days ago...`n" | Out-File -FilePath $outfileName -Append 
}
else{
    Write-Host "`nPulling CCS Audit Logs from $days day ago...`n" 
    write-output "`n$dateTime    INFO    Pulling CCS Audit Logs from $days day ago...`n" | Out-File -FilePath $outfileName -Append 
}

# composing Audit Pull Payload data
$entityTypes = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/audit-logs/entity-types?service=Dmaas" -Method 'GET' -Headers $headers 

$actions = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/audit-logs/actions?service=Dmaas" -Method 'GET' -Headers $headers 

if($actions) {
    $actionsJn = ($actions.actions -join ",")

    # Audit Pull
    write-host "Calling Audiit Pull with: Invoke-RestMethod https://helios.cohesity.com/v2/mcm/audit-logs?startTimeUsecs=$starttimeusecs&serviceContext=Dmaas&regionIds=$regionIds&endTimeUsecs=$endtimeusecs&count=1000&actions=$actionsJn -Method 'GET'`n"

    write-output "$dateTime    INFO    Calling Audiit Pull with: Invoke-RestMethod https://helios.cohesity.com/v2/mcm/audit-logs?startTimeUsecs=$starttimeusecs&serviceContext=Dmaas&regionIds=$regionIds&endTimeUsecs=$endtimeusecs&count=1000&actions=$actionsJn -Method 'GET'`n" | Out-File -FilePath $outfileName -Append 

    $response = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/audit-logs?startTimeUsecs=$starttimeusecs&serviceContext=Dmaas&regionIds=$regionIds&endTimeUsecs=$endtimeusecs&count=1000&actions=$actionsJn" -Method 'GET' -Headers $headers 


    if($response){
        # formatting and saving Audit Logs
        $jsonLogs = $response | ConvertTo-Json
        Write-Output "$jsonLogs" | Set-Content -path $auditLogs\CCS-Audit-Logs_$dateString.json

        # write-host $jsonLogs 

        write-host "CCS Audit Logs SUCCESSFULLY saved to: $auditLogs\CCS-Audit-Logs_$dateString.json`n" -ForegroundColor Green
        write-output "$dateTime    INFO    CCS Audit Logs SUCCESSFULLY saved to: $auditLogs\CCS-Audit-Logs_$dateString.json`n" | Out-File -FilePath $outfileName -Append

        if($uri){
            $payload = [PSCustomObject]@{
                content = $response
            }
            try{
            $webhook = Invoke-RestMethod -Uri $uri -Method Post -Body ($payload | ConvertTo-Json)
            
            }
            catch{
                write-error -message $_
                $currError = $true
                write-host "Webhook Push to $uri FAILED!`n" -ForegroundColor Red
                write-output "$dateTime    FAIL    Webhook Push to $uri FAILED!`n" | Out-File -FilePath $outfileName -Append
            }
        
            if(!$currError){
                write-host "Webhook Push to $uri SUCCESSFUL!`n" -ForegroundColor Green
                write-output "$dateTime    INFO    Webhook Push to $uri SUCCESSFUL!`n" | Out-File -FilePath $outfileName -Append
            }
            
        }
        else{
            write-host "No Webhook designated`n" -ForegroundColor Green
            write-output "$dateTime    INFO    No Webhook designated`n" | Out-File -FilePath $outfileName -Append
        }

    }
    else{
        write-host "Audit Pull FAILED!`n" -ForegroundColor Red
        write-output "$dateTime    FAIL    Audit Pull FAILED!`n" | Out-File -FilePath $outfileName -Append
    }
}
else{
    write-host "Audit Pull FAILED! The appropriate CCS Parameters could not be called.`n" -ForegroundColor Red
    write-output "$dateTime    FAIL    Audit Pull FAILED! The appropriate CCS Parameters could not be called.`n" | Out-File -FilePath $outfileName -Append
}


    
    


