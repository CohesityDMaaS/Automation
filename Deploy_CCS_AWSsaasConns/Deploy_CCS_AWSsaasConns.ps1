
# ./Deploy_CCS_AWSsaasConns.ps1 -apiKey #### -CCSregionId us-east-1 -AWSregionId us-east-1 -AWSid #### -subnetId subnet-#### -securityGroupId sg-#### -vpcId vpc-#### -saasNo 2 -AWStag "label=value", "label=value" -connAdd

# install PowerShell, if on macOS: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-macos?view=powershell-7.2
# upgrade PowerShell Module to current revision of 7.2.4: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.2#msi


# process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apiKey,  # apiKey generated in CCS UI
    [Parameter(Mandatory = $True)][string]$CCSregionId,  # CCS region where AWS is Registered
    [Parameter(Mandatory = $True)][string]$AWSid,  # AWS Account ID
    [Parameter(Mandatory = $True)][string]$AWSregionId,  # AWS region where SaaS Connector EC2 Instance will be deployed 
    [Parameter(Mandatory = $True)][string]$subnetId,  # AWS Subnet Identifier
    [Parameter(Mandatory = $True)][string]$securityGroupId,  # AWS Network Security Group
    [Parameter(Mandatory = $True)][string]$vpcId,  # AWS VPC Id
    [Parameter()][int]$saasNo = 1,  # (optional) Number of AWS SaaS Connector EC2 Instances to create
    [Parameter()][array]$AWStag,  # (optional) AWS SaaS Connector EC2 Instance Tags (comma separated)
        # example: "label=value", "label2=value2"
    [Parameter()][string]$AWStags = ''  # (optional) text file of AWS SaaS Connector EC2 Instance Tags (one per line)
         # example: "label=value"
         #          "label2=value2"
    # [Parameter()][switch]$connAdd  # (optional) call adding additional SaaS Connectors to already existing Connections
    # [Parameter()][string]$groupName = ''  # (optional) ONLY USE IN CONJUNCTION WITH $connAdd switch to identify SaaS Connector Group Name
)


# set static variables
$dateString = (get-date).ToString('yyyy-MM-dd')
$dateTime = Get-Date -Format "dddd MM/dd/yyyy HH:mm"
$outfileName = "$PSScriptRoot\log-Deploy_CCS_AWSsaasConns-$dateString.txt"

# logging
function info_log{
    param ($statement)
    
    Write-Host "`nINFO    $statement`n" -ForegroundColor Blue
    Write-Output "`n$dateTime    INFO    $statement`n" | Out-File -FilePath $outfileName -Append
}

function warn_log{
    param ($statement)
    
    Write-Host "`nWARN    $statement`n" -ForegroundColor Yellow
    Write-Output "`n$dateTime    WARN    $statement`n" | Out-File -FilePath $outfileName -Append
}

function fail_log{
    param ($statement)
    
    Write-Host "`nFAIL    $statement`n" -ForegroundColor Red
    Write-Output "`n$dateTime    FAIL    $statement`n" | Out-File -FilePath $outfileName -Append
}

function pass_log{
    param ($statement)
    
    Write-Host "`nPASS    $statement`n" -ForegroundColor Green
    Write-Output "`n$dateTime    PASS    $statement`n" | Out-File -FilePath $outfileName -Append
}

# ensure the environment meets the PowerShell Module requirements of 5.1 or above 

info_log "Validating PowerShell Version..."
$version = $PSVersionTable.PSVersion
if($version.major -lt 5.1){
    warn_log "Please upgrade the PowerShell Module to the current revision of 7.2.4 by downloading from the Microsoft site: `nhttps://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.2#msi"
}
else {
    pass_log "PowerShell Module is up to date."
}


# gather list of AWS Tag's to Associate with SaaS Connector EC2 Instance
$tagsToAdd = @()
if('' -ne $AWStag){
    info_log "Gathering list of AWS Tag's to Associate with SaaS Connector EC2 Instance..."
    foreach($tag in $AWStag){
        $tagsToAdd += $tag
    }
}
if('' -ne $AWStags){
    info_log "Gathering list of AWS Tag's to Associate with SaaS Connector EC2 Instance..."
    if(Test-Path -Path $AWStags -PathType Leaf){
        $AWStag = Get-Content $AWStags
        foreach($tag in $AWStag){
            $tagsToAdd += [string]$tag
        }
    }else{
        fail_log "AWS SaaS Connector Tags file $AWStags not found at specified directory!"
        exit
    }
}

$tagsToAdd = @($tagsToAdd | Where-Object {$_ -ne ''})

if($tagsToAdd.Count -gt 0){
    pass_log "AWS SaaS Connector Tags parsed SUCCESSFULLY: `n$tagsToAdd" 
}

# source the cohesity-api helper code
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)

info_log "Connecting to CCS..."

# authenticate
apiauth -password $apiKey -regionid $CCSregionId

# validate CCS Tenant ID
info_log "Validating Tenant ID..."  
$sessionUser = api get sessionUser
$tenantId = $sessionUser.tenantId

if(!$tenantId){
    fail_log "No CCS Tenant ID found!" 
    exit
}
else{
    pass_log "Tenant ID: $tenantId" 
}

info_log "Pulling AWS Source Info..." 

$awsSources = (api get -mcmv2 "data-protect/sources?environments=kAWS")
$awsSource = $awsSources.sources | where-object {$_.name -eq "$AWSid"}
$awsSourceId = $awsSource.sourceInfoList.sourceId
$regId = $awsSource.sourceInfoList.registrationId

pass_log "CCS Registration ID for AWS Account $AWSid : $regId" 

$rigelInfo = (api get -mcmv2 "data-protect/sources/registrations/$regId")
if ($rigelInfo.connections -ne "[]") {
    $groupId = $rigelInfo.connections.connectionId
    if($null -ne $groupId){
        $groupConns = (api get -mcmv2 "rigelmgmt/rigel-groups?tenantId=$tenandId&regionId=$CCSregionId&getConnectionStatus=true&fetchConnectorGroups=true&groupId=$groupId")
        $groups = $groupConns.rigelGroups
        $grpConnectors = $groupConns.rigelGroups.expectedNumberOfRigels
        if($null -ne $grpConnectors){
            $status = $groupConns.rigelGroups.status
            pass_log "Verified current amount of SaaS Connectors associated with AWS Account '$AWSid': $grpConnectors"

            warn_log "Current SaaS Connections have been detected in association with AWS Account ID: $AWSid" 
            $addOverride = read-host -prompt "`nDo you need to add $saasNo more Connector(s) to current SaaS Connections for AWS Account '$AWSid'? (y/n)" 
            if ($addOverride -eq "n") {
                info_log "You have chosen not to add more Connectors to current SaaS Connections for AWS Account '$AWSid'"
                warn_log "Please resolve descrepancy manually and try running script again..."
                exit
            }
            elseif ($addOverride -eq "y") {
                info_log "You have chosen to add $saasNo more Connectors to current SaaS Connections for AWS Account '$AWSid'"
                $additional = $true
            } 
        }
        else{
            warn_log "No current SaaS Connections have been detected in association with AWS Account ID: $AWSid" 
            $addOverride = read-host -prompt "`nDo you need to add $saasNo New SaaS Connector(s) to AWS Account '$AWSid'? (y/n)" 
            if ($addOverride -eq "n") {
                info_log "You have chosen not to add New SaaS Connectors to AWS Account $AWSid"
                warn_log "Please resolve descrepancy manually and try running script again..."
                exit
            }
            elseif ($addOverride -eq "y") {
                info_log "You have chosen to add $saasNo New SaaS Connector(s) to AWS Account $AWSid"
                $new = $true
            } 
        }
    }
    else{
        warn_log "No current SaaS Connections have been detected in association with AWS Account ID: $AWSid" 
        $addOverride = read-host -prompt "`nDo you need to add $saasNo New SaaS Connector(s) to AWS Account '$AWSid'? (y/n)" 
        if ($addOverride -eq "n") {
            info_log "You have chosen not to add New SaaS Connectors to AWS Account $AWSid"
            warn_log "Please resolve descrepancy manually and try running script again..."
            exit
        }
        elseif ($addOverride -eq "y") {
            info_log "You have chosen to add $saasNo New SaaS Connector(s) to AWS Account $AWSid"
            $new = $true
        } 
    }
}

    

if($additional -eq $true){
    # creating Paylog for CCS API call
    [int]$addConns = [int]$grpConnectors + [int]$saasNo

    $payload = @{
        "currentNumOfConnectors" = $grpConnectors; 
        "numberOfConnectors" = $addConns;
        "ConnectionId" = $groupId
    }

    # deploy additional AWS SaaS Connector to current Source Connections
    info_log "Adding SaaS Connectors to already existing SaaS Connections - Payload: `n$payload" 
    $addition = (api put -mcmv2 rigelmgmt/rigel-groups $payload) 
    $addition | ConvertTo-Json

    if($addition){
        pass_log "Addition of SaaS Connectors to current SaaS Connections associated with AWS Accouut ID $AWSid SUCCESSFUL!" 
        info_log "Verifying SaaS Connector Connection Status to AWS Source..."
        $groupID = $addition.ConnectionId

        $groupConns = (api get -mcmv2 "rigelmgmt/rigel-groups?tenantId=$tenandId&regionId=$CCSregionId&getConnectionStatus=true&fetchConnectorGroups=true&groupId=$groupID")
        if($groupConns){
            $status = $groupConns.rigelGroups.status
            $useCase = $groupConns.rigelGroups.useCase
            $grpConnectors = $groupConns.rigelGroups.expectedNumberOfRigels
            $securityId = $groupConns.rigelGroups.rigelCloudInfraInfo.awsRigelInfraInfo.securityGroupId
            $subnetId = $groupConns.rigelGroups.rigelCloudInfraInfo.awsRigelInfraInfo.subnetId
            $vpcId = $groupConns.rigelGroups.rigelCloudInfraInfo.awsRigelInfraInfo.vpcId
            pass_log "Verified the following data related to all SaaS Connectors associated with AWS Account '$AWSid': `nNumber of SaaS Connectors: $grpConnectors `nSaaS Connection Status: $status `nSaaS Connection Use Case: $useCase `nSaaS Connection Security Group ID: $securityId `nSaaS Connection Subnet ID: $subnetId `nSaaS Connection VPC Id: $vpcId"
            
            foreach($rigel in $groupConns.rigelGroups.connectorGroups.connectors){
                $connHealth = $rigel.dataPlaneConnectionStatus
                $rigelIp = $rigel.rigelIp
                $rigelName = $rigel.rigelName
                $rigelSWver = $rigel.softwareVersion
                pass_log "Verified the following data per SaaS Connector: `nSaaS Connector Name: $rigelName `nSaaS Connector Software Version: $rigelSWver `nSaaS Connector IP Address: $rigelIp `nSaaS Connector Health: $connHealth"
            }
        }
        else{
            fail_log "No current SaaS Connections have been detected in association with AWS Account ID: $AWSid"
            exit
        }
    }
    else{
        fail_log "Addition of SaaS Connectors to current SaaS Connections associated with AWS Accouut ID $AWSid UNSUCCESSFUL!"
        exit
    }
}


elseif($new -eq $true){
    # create Payload for CCS API call
    info_log "Preparing payload for New CCS AWS SaaS Connector Creation..."
    
    $body = @{
        "tenantId" = "$tenantId";
        "connectorType" = "AWS";
        "useCase" = "Ec2Backup";
        "name" = "$AWSid-$AWSregionId-$CCSregionId";
        "numberOfRigels" = $saasNo;
        "regionId" = "$CCSregionId";
        "rigelCloudInfraInfo" = @{
            "awsRigelInfraInfo" = @{
                "accountNumber" = "$AWSid";
                "regionId" = "$AWSregionId";
                "subnetId" = "$subnetId";
                "securityGroupId" = "$securityGroupId";
                "vpcId" = "$vpcId";
                "tags" = @()
                    
            }
        }
    }

    if($tagsToAdd -gt 0){
        foreach($tagToAdd in $tagsToAdd){
            $tag = $tagToAdd -split "="
            $hashTable = [ordered] @{"key" = $tag[0]; "value" = $tag[1]}
                write-host $hashTable
                $body.rigelCloudInfraInfo.awsRigelInfraInfo.tags += $hashTable; 
            }  
        }

    # prepare body of REST API Call
    write-host "Body Value: `n" $body
    #$bodyJson = $body | ConvertTo-Json 
    info_log "Creation of New CCS SaaS Connector for AWS - Payload: `n$body"  

    warn_log "*****Launching SaaS Connector in your selected subnets. This could take a few minutes.*****" 

    # create new AWS SaaS Connector
    $addition = (api post -mcmv2 rigelmgmt/rigel-groups $body)     
    $addition | ConvertTo-Json

    if($addition){
        pass_log "Creation of New CCS SaaS Connector for AWS Accouut ID $AWSid SUCCESSFUL!" 
        info_log "Verifying SaaS Connector Connection Status to AWS Source..."
        $groupID = $addition.groupId

        $groupConns = (api get -mcmv2 "rigelmgmt/rigel-groups?tenantId=$tenandId&regionId=$CCSregionId&getConnectionStatus=true&fetchConnectorGroups=true&groupId=$groupID")
        if($groupConns){
            $status = $groupConns.rigelGroups.status
            $useCase = $groupConns.rigelGroups.useCase
            $grpConnectors = $groupConns.rigelGroups.expectedNumberOfRigels
            $securityId = $groupConns.rigelGroups.rigelCloudInfraInfo.awsRigelInfraInfo.securityGroupId
            $subnetId = $groupConns.rigelGroups.rigelCloudInfraInfo.awsRigelInfraInfo.subnetId
            $vpcId = $groupConns.rigelGroups.rigelCloudInfraInfo.awsRigelInfraInfo.vpcId
            pass_log "Verified the following data related to all SaaS Connectors associated with AWS Account '$AWSid': `nNumber of SaaS Connectors: $grpConnectors `nSaaS Connection Status: $status `nSaaS Connection Use Case: $useCase `nSaaS Connection Security Group ID: $securityId `nSaaS Connection Subnet ID: $subnetId `nSaaS Connection VPC Id: $vpcId"
            
            foreach($rigel in $groupConns.rigelGroups.connectorGroups.connectors){
                $connHealth = $rigel.dataPlaneConnectionStatus
                $rigelIp = $rigel.rigelIp
                $rigelName = $rigel.rigelName
                $rigelSWver = $rigel.softwareVersion
                pass_log "Verified the following SaaS Connector data associated with AWS Account '$AWSid': `nSaaS Connector Name: $rigelName `nSaaS Connector Software Version: $rigelSWver `nSaaS Connector IP Address: $rigelIp `nSaaS Connector Health: $connHealth"
            }
        }
        else{
            fail_log "No current SaaS Connections have been detected in association with AWS Account ID: $AWSid"
            exit
        }
    }
    else{
        fail_log "Creation of New CCS SaaS Connector for AWS Accouut ID $AWSid UNSUCCESSFUL!"
        exit
    }
}


# # Optional: Associate newly created AWS Saas Connections to CCS AWS Source$awsInfo = (api get -mcmv2 "dms/tenants/regions/aws-cloud-source?tenantId=$tenantId&destinationRegionId=$AWSregionId&awsAccountNumber=$AWSid")
        # $iam_role_arn = $awsInfo.awsIamRoleArn
        # $cp_role_arn = $awsInfo.tenantCpRoleArn

        # $rigelInfo = (api get -mcmv2 "data-protect/sources/registrations/$regId")
        # $subscription = $rigelInfo.awsParams.subscriptionType

        # $updatedConn = @()
        # if ($rigelInfo.connections -ne '[]') {
        #     # Filter out the connection where connectionId matches group_id
        #     $connectors = $rigelInfo.connections
        #     foreach($connector in $connectors){
        #         if($connectors){
        #             $connectionId = $connectors.connectionId
        #             $entityId = $connectors.entityId
        #             $connectorGroupId = $connectors.connectorGroupId
        #             $updatedConn += @{
        #                 "connectionId" = $connectionId;
        #                 "entityId" = $entityId;
        #                 "connectorGroupId" = $connectorGroupId
        #             }
        #         }
        #     }
        # }
        # else{
        #     $entities = (api get -mcmv2 "data-protect/objects?parentId=$awsSourceId")
        #     $entity = $entities.objects | where-object {$_.name -eq "$CCSregionId"}
        #     $entityId = $entity.id
        #     $connectionId = $addition.ConnectionId
        #     $connectorGroupId = -1
        #     $updatedConn += @{
        #         "connectionId" = $connectionId;
        #         "entityId" = $entityId;
        #         "connectorGroupId" = $connectorGroupId
        #     }
        # }


        # info_log "Preparing payload for the Assocation of new SaaS Connectors to AWS Account $AWSid"
        
        # $body = @{
        #     "environment" = "kAWS";
        #     "awsParams" = @{
        #         "subscriptionType" = "$subscription";
        #         "standardParams" = @{
        #             "authMethodType" = "kUseIAMRole";
        #             "iamRoleAwsCredentials" = @{
        #                 "iamRoleArn" = "$iam_role_arn";
        #                 "cpIamRoleArn" = "$cp_role_arn"

        #             }
        #         }
        #     };
        #     "connections" = $updatedConn
        # }

        # # prepare body of REST API Call
        # info_log "Assocation of new SaaS Connectors to AWS Account '$AWSid' - Payload: `n$body"   

        # info_log "Assocating new SaaS Connectors to AWS Account $AWSid..." 
        # $association = (api put -mcmv2 "data-protect/sources/registrations/$regId" $body)      
        # $association | ConvertTo-Json

        # if($association){
        #     pass_log "Assocation of new SaaS Connectors to AWS Account '$AWSid' SUCCESSFUL!"
        # }

        # else{
        #     fail_log "Assocation of new SaaS Connectors to AWS Account '$AWSid' UNSUCCESSFUL!"
        # }



  # # modified AWS Saas Connections on CCS AWS Source
        # $awsInfo = (api get -mcmv2 "dms/tenants/regions/aws-cloud-source?tenantId=$tenantId&destinationRegionId=$AWSregionId&awsAccountNumber=$AWSid")
        # write-host $awsInfo
        # $iam_role_arn = $awsInfo.awsIamRoleArn
        # $cp_role_arn = $awsInfo.tenantCpRoleArn
        
        # $rigelInfo = (api get -mcmv2 "data-protect/sources/registrations/$regId")
        # $subscription = $rigelInfo.awsParams.subscriptionType

        # $updatedConn = @()
        # if ($rigelInfo.connections -ne '[]') {
        #     # Filter out the connection where connectionId matches group_id
        #     $connectors = $rigelInfo.connections #| Where-Object {$_.connectionId -ne $groupId}  
        #     foreach($connector in $connectors){
        #         if($connectors){
        #             $connectionId = $connectors.connectionId
        #             $entityId = $connectors.entityId
        #             $connectorGroupId = $connectors.connectorGroupId
        #             $updatedConn += @{
        #                 "connectionId" = $connectionId;
        #                 "entityId" = $entityId;
        #                 "connectorGroupId" = $connectorGroupId
        #             }
        #         }
        #     }
        # }
        # else{
        #     $entities = (api get -mcmv2 "data-protect/objects?parentId=$awsSourceId")
        #     $entity = $entities.objects | where-object {$_.name -eq "$CCSregionId"}
        #     $entityId = $entity.id
        #     $connectionId = $addition.ConnectionId
        #     $connectorGroupId = -1
        #     $updatedConn += @{
        #         "connectionId" = $connectionId;
        #         "entityId" = $entityId;
        #         "connectorGroupId" = $connectorGroupId
        #     }
        # }


        # info_log "Preparing payload for the Assocation of new SaaS Connectors to AWS Account $AWSid"
        
        # $body = @{
        #     "environment" = "kAWS";
        #     "awsParams" = @{
        #         "subscriptionType" = "$subscription";
        #         "standardParams" = @{
        #             "authMethodType" = "kUseIAMRole";
        #             "iamRoleAwsCredentials" = @{
        #                 "iamRoleArn" = "$iam_role_arn";
        #                 "cpIamRoleArn" = "$cp_role_arn"

        #             }
        #         }
        #     };
        #     "connections" = $updatedConn
        # }

        # # prepare body of REST API Call
        # info_log "Assocation of new SaaS Connectors to AWS Account '$AWSid' - Payload: `n$body"   

        # info_log "Assocating new SaaS Connectors to AWS Account $AWSid..." 
        # $association = (api put -mcmv2 "data-protect/sources/registrations/$regId" $body)     
        # $association | ConvertTo-Json

        # if($association){
        #     pass_log "Assocation of new SaaS Connectors to AWS Account '$AWSid' SUCCESSFUL!"
        # }

        # else{
        #     fail_log "Assocation of new SaaS Connectors to AWS Account '$AWSid' UNSUCCESSFUL!"
        # }

# $rigelInfo = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/data-protect/sources/registrations/$regId" -Method 'GET' -headers $headers
# $groupId = $rigelInfo.connections.connectionId 
# $entityId = $rigelInfo.connections.entityId

# $rigelInfo = $rigelInfo.connections | ConvertFrom-Json
# write-host $rigelInfo



# if ($groupId) {
#     Write-host "`nCCS AWS SaaS Connector Group ID: $groupId`n" 
#     write-output "`n$dateTime    INFO    CCS AWS SaaS Connector Group ID: $groupId`n" | Out-File -FilePath $outfileName -Append 

#     $saasConn = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/rigelmgmt/rigel-groups?tenantId=$tenandId&maxRecordLimit=1000&fetchConnectorGroups=true" -Method 'GET' -headers $headers
#     $saasConn = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/rigelmgmt/rigel-groups?tenantId=$tenandId&regionId=$CCSregionId&groupId=$groupId&getConnectionStatus=true" -Method 'GET' -headers $headers
#     $saasConnNum = $saasConn.rigelGroups.expectedNumberOfRigels
#     # UPDATE
#     # $saasConn = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/rigelmgmt/rigel-groups?tenantId=$tenandId&groupId=$groupId&fetchToken=true" -Method 'GET' -headers $headers
#     # $saasConnNum = $saasConn.rigelGroups.expectedNumberOfRigels

#     Write-host "`nNumber of CCS AWS SaaS Connectors already implemented: $saasConnNum`n" 
#     write-output "`n$dateTime    INFO    Number of CCS AWS SaaS Connectors already implemented: $saasConnNum`n" | Out-File -FilePath $outfileName -Append 


#     if($saasConnNum -gt 0 -and $connAdd -eq $false){
#         Write-host "`nThis CCS AWS Source already has $saasConnNum SaaS Connector(s) deployed!`n" -ForegroundColor Yellow
#         write-output "`n$dateTime    WARN    This CCS AWS Source already has $saasConnNum SaaS Connector(s) deployed!`n" | Out-File -FilePath $outfileName -Append 

#         $connAddOverride = read-host -prompt "`nDo you need to add additional CCS AWS SaaS Connectors to the already existing CCS AWS SaaS Connector Group? (y/n)"
#         write-output "`n$dateTime    WARN    Do you need to add additional CCS AWS SaaS Connectors to the already existing CCS AWS SaaS Connector Group? (y/n)`nUSER RESPONSE: $connAddOverride" | Out-File -FilePath $outfileName -Append 

#         if ($connAddOverride -eq "y") {
#             $connAddOverride = $true
#         } elseif ($connAddOverride -eq "n") {
#             $connAddOverride = $false
#         }

#         if($connAddOverride -eq $false){
#             Write-host "`nIf you are attempting to to create a new CCS AWS SaaS Connector Group in addition to the one which already exists, please know that Cohesity only supports one Connector Group per AWS Region.`n" -ForegroundColor Yellow
#             write-output "`n$dateTime    WARN    If you are attempting to to create a new CCS AWS SaaS Connector Group in addition to the one which already exists, please know that Cohesity only supports one Connector Group per AWS Region.`n" | Out-File -FilePath $outfileName -Append 
#         }
#         else{
#             $connAdd = $true
#             Write-host "`nEnabled the 'connAdd' switch to perform an addition to the already existing AWS SaaS Connector Group.`n" -ForegroundColor Green
#             write-output "`n$dateTime    INFO    Enabled the 'connAdd' switch to perform an addition to the already existing AWS SaaS Connector Group.`n" | Out-File -FilePath $outfileName -Append
#         }
#     }
# }