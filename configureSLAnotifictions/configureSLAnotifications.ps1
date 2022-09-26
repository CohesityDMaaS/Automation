
# ./configureSLAnotifications.ps1 -apiKey ****** -regionId us-east-1 -ruleName "SLA_Alerts" -emailAddresses "test@duh.com, blah@test.com" -violations All -source server.domain.com

# process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apiKey,  # apiKey
    [Parameter(Mandatory = $True)][string]$regionId,  # DMaaS SQL Source Region Id
    [Parameter(Mandatory = $True)][string]$ruleName,  # SLA Alert Notification Rule Name
    [Parameter(Mandatory = $True)][string]$source, # reference Registered Source to validate DMaaS Cluster
    [Parameter()][string]$emailAddresses = '',  # emails addresses that will be notified to SLA Violations
    [Parameter()][string]$violations,  # All or choose individual violation to configure - if individual violations are chosen, this variable is not set
    [Parameter()][bool]$objectBackupSlaViolated,  # true ObjectBackupSlaViolated violation set
    [Parameter()][bool]$protectedObjectSlaViolated,  # true ProtectedObjectSlaViolated violation set
    [Parameter()][bool]$protectionGroupSlaViolated  # true ProtectionGroupSlaViolated violation set
    


)

# outfile
$dateString = (get-date).ToString('yyyy-MM-dd')
$outfileName = "log-configureSLAnotifications-$dateString.txt"

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
$headers.Add("content-type", "application/json")
$tenant = Invoke-RestMethod 'https://helios.cohesity.com/irisservices/api/v1/mcm/userInfo' -Method 'GET' -Headers $headers

$tenantId = $tenant.user.profiles.tenantId 
$origTenantId = $tenantId.split(':')
$updatedTenantId = $origTenantId[1]
# $updatedAccountId = $origTenantId[0]

Write-host "Tenant ID: " $tenantId
write-host "Updated Tenant ID: " $updatedTenantId
$accountId = $tenant.user.salesforceAccount.accountId
Write-host "Account ID: " $accountId

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

# determine Cluster ID
Write-Host "Finding Source $source"

$sources = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/data-protect/sources" -Method 'GET' -Headers $headers

$sourceInfo = $sources.sources | where-object {$_.name -eq "$source"}

$sourceId = $sourceInfo.sourceInfoList.registrationId
$clusterId = $sourceId.split(':')
[int64]$clusterId = $clusterId[0]

write-host "Cluster Id: $clusterId"

# register Physical Server
$headers.Add("regionId", "$regionId")


    # $body = "{
    #     `"accountId`": `"$accountId`",
    #     `"alertNames`": [
    #         `"ObjectBackupSlaViolated`",
    #         `"ProtectedObjectSlaViolated`",
    #         `"ProtectionGroupSlaViolated`"
    #     ],
    #     `"categories`": null,
    #     `"clusterIds`": [
    #         $clusterId
    #     ],
    #     `"email_configs`": [
    #         {
    #             `"cc`": null,
    #             `"options`": null,
    #             `"to`": [
    #                 `"$emailAddresses`"
    #             ]
    #         }
    #     ],
    #     `"groupLabelNames`": null,
    #     `"labels`": null,
    #     `"pagerduty_configs`": null,
    #     `"ruleId`": `"62b2af693e30beabecca2f3d`",
    #     `"ruleName`": `"SLA Notifications`",
    #     `"severities`": [
    #         `"Critical`"
    #     ],
    #     `"slack_configs`": null,
    #     `"tenantId`": `"$tenantId`",
    #     `"typebuckets`": [
    #         `"DataService`"
    #     ],
    #     `"webhook_configs`": null
    # }"
    
    $body = @{
        "accountId" = $accountId;
        "alertNames" = @(
            # "ObjectBackupSlaViolated";
            # "ProtectedObjectSlaViolated";
            # "ProtectionGroupSlaViolated"
        );
        "categories" = $null;
        "clusterIds" = @(
            $clusterId
        );
        "email_configs" = @(
            @{
                "cc" = $null;
                "options" = $null;
                "to" = @(
                    "$emailAddresses"
                )
            }
        );
        "groupLabelNames" = $null;
        "labels" = $null;
        "pagerduty_configs" = $null;
        "ruleId" = "62b2af693e30beabecca2f3d";
        "ruleName" = "$ruleName";
        "severities" = @();
        "slack_configs" = $null;
        "tenantId" = "$updatedTenantId";
        "typebuckets" = @(
            "DataService"
        );
        "webhook_configs"= $null
    }

    # $validate = @{
    #     "accountId" = $updatedAccountId;
    #     "tenantId" = "$updatedTenantId";
    # }

    if($violations -eq 'All'){
        $body.alertNames = @(
            "ObjectBackupSlaViolated";
            "ProtectedObjectSlaViolated";
            "ProtectionGroupSlaViolated"
            )   
        write-host "ALL" 
    }
        
        # $body = @($body + @{
        #     "alertNames" = @(
        #         "ObjectBackupSlaViolated";
        #         "ProtectedObjectSlaViolated";
        #         "ProtectionGroupSlaViolated"
        #         )
        #     }
        # )
        

    if($objectBackupSlaViolated -eq $true){
        $body.alertNames = @($body.alertNames + @(
                "ObjectBackupSlaViolated"
                )
            )
        }

    if($protectedObjectSlaViolated -eq $true){
        $body.alertNames = @($body.alertNames + @(
                "ProtectedObjectSlaViolated"
                )
            )
        }

    if($protectionGroupSlaViolated -eq $true){
        $body.alertNames = @($body.alertNames + @(
                "ProtectionGroupSlaViolated"
                )
            )
        }

    if($sourceInfo){

        Write-Host "Configuring SLA Notifications for Cluster ID $clusterId..."

        $bodyJson = $body | ConvertTo-Json 
        write-host "$bodyJson"   
        $bodyJson = ConvertTo-Json -Compress -Depth 99 $body 

        $response = Invoke-RestMethod 'https://helios.cohesity.com/v2/mcm/alert-service/alerts/config/notificationRules' -Method 'POST' -Headers $headers -Body $bodyJson -ContentType 'application/json' 
        $response | out-file -filepath ./$outfileName -Append

        $validation = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/alert-service/alerts/metadata/typebucket?accountId=$accountId&tenantId=$tenantId" -Method 'GET' -Headers $headers -ContentType 'application/json' 
        write-host "`n$validation"
        $validation | out-file -filepath ./$outfileName -Append

        #$validateJson = $validate | ConvertTo-Json 
        # write-host "$validateJson"   
        #$validateJson = ConvertTo-Json -Compress -Depth 99 $validate

        # $validation = Invoke-RestMethod 'https://helios.cohesity.com/v2/mcm/alert-service/alerts/config/notificationRules' -Method 'GET' -Headers $headers -Body $validate -ContentType 'application/json' 
        # write-host $validation
       
        Write-host "$response"
    }

    else{
    Write-Host "Set SLA Notifications for Cluster ID $clusterId" -ForegroundColor Yellow
    }
