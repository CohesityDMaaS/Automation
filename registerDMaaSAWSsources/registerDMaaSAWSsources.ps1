
# ./registerDMaaSAWSsources.ps1 -apiKey #### -regionId us-east-1 -AWSid #### -roleARN "AWS_ARN"

# install PowerShell on macOS: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-macos?view=powershell-7.2
# install AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html#getting-started-install-instructions
# install AWS CLI for Powershell: https://matthewdavis111.com/aws/deploy-cloudformation-powershell/


# process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apiKey,  # apiKey
    [Parameter(Mandatory = $True)][string]$regionId,  # DMaaS SQL Source Region Id
    [Parameter()][array]$AWSid,  # AWS Account ID
    [Parameter()][string]$AWSlist = '',  # optional textfile of AWS Account Id's to protect
    [Parameter()][string]$roleARN,  # AWS ARN associated with CFT Deployment IAM Role
    [Parameter()][string]$ARNlist = ''  # optional textfile of AWS ARN's associated with CFT Deployment IAM Roles
)

# set static variables
$dateString = (get-date).ToString('yyyy-MM-dd')
$outfileName = "$PSScriptRoot\log-registerDMaasAWS-$dateString.txt"
$finalOutput = "$PSScriptRoot\log-DMaaSAWSinfo-$dateString.txt"

# create CFT folder
$cftFolder = "CFT"

    if (Test-Path $PSScriptRoot\$cftFolder) {
    
        Write-Host "CFT Folder already exists."
        Write-Output "CFT Folder already exists." | Out-File -FilePath $outfileName -Append 
    }
    else {
    
        #PowerShell Create directory if not exists
        New-Item $cftFolder -ItemType Directory
        Write-Host "CFT Folder Created SUCCESSFULLY!" -ForegroundColor Green
        Write-Output "CFT Folder Created SUCCESSFULLY!" | Out-File -FilePath $outfileName -Append 
    }

    $awsCFT = "$PSScriptRoot\$cftFolder"

# ensure the environment meets the PowerShell Module requirements of 5.1 or above 

write-host "`nValidating PowerShell Version...`n"
Write-Output "`nValidating PowerShell Version...`n" | Out-File -FilePath $outfileName -Append
$version = $PSVersionTable.PSVersion
if($version.major -lt 5.1){
    write-host "Please upgrade the PowerShell Module to the current revision of 7.2.4 by downloading from the Microsoft site:" 
    Write-Output "Please upgrade the PowerShell Module to the current revision of 7.2.4 by downloading from the Microsoft site:" | Out-File -FilePath $outfileName -Append
    write-host "https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.2#msi" 
    write-output "https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.2#msi" | Out-File -FilePath $outfileName -Append
}
else {
    write-host "PowerShell Module is up to date." 
    Write-Output "PowerShell Module is up to date." | Out-File -FilePath $outfileName -Append
}

# gather list of AWS ID's to Register
$AWStoAdd = @()
foreach($AWS in $AWSid){
    $AWStoAdd += $AWS
}
if ('' -ne $AWSlist){
    if(Test-Path -Path $AWSlist -PathType Leaf){
        $AWSid = Get-Content $AWSlist
        foreach($AWS in $AWSid){
            $AWStoAdd += [string]$AWS
        }
    }else{
        Write-Host "`nAWS ID list $AWSlist not found!" -ForegroundColor Yellow 
        Write-Output "`nAWS ID list $AWSlist not found!" | Out-File -FilePath $outfileName -Append 
        exit
    }
}

$AWStoAdd = @($AWStoAdd | Where-Object {$_ -ne ''})

if($AWStoAdd.Count -eq 0){
    Write-Host "`nNo AWS ID's specified!" -ForegroundColor Yellow  
    Write-Output "`nNo AWS ID's specified!" | Out-File -FilePath $outfileName -Append 
    exit
}else{
    Write-Host "`nAWS ID's parsed SUCCESSFULLY!`n" -ForegroundColor Green 
    Write-Output "`nAWS ID's parsed SUCCESSFULLY!`n" | Out-File -FilePath $outfileName -Append 
    write-output $AWStoAdd | Out-File -FilePath $outfileName -Append 
}

# gather list of AWS ARN's to use to Register
$ARNtoAdd = @()
foreach($ARN in $roleARN){
    $ARNtoAdd += $ARN
}
if ('' -ne $ARNlist){
    if(Test-Path -Path $ARNlist -PathType Leaf){
        $roleARN = Get-Content $ARNlist
        foreach($ARN in $roleARN){
            $AWStoAdd += [string]$ARN
        }
    }else{
        Write-Host "`nAWS ARN list $ARNlist not found!" -ForegroundColor Yellow 
        Write-Output "`nAWS ARN list $ARNlist not found!" | Out-File -FilePath $outfileName -Append 
        exit
    }
}

$ARNtoAdd = @($ARNtoAdd | Where-Object {$_ -ne ''})

if($ARNtoAdd.Count -eq 0){
    Write-Host "`nNo AWS ID's specified!" -ForegroundColor Yellow  
    Write-Output "`nNo AWS ID's specified!" | Out-File -FilePath $outfileName -Append 
    exit
}else{
    Write-Host "`nAWS ARN's parsed SUCCESSFULLY!`n" -ForegroundColor Green 
    Write-Output "`nAWS ARN's parsed SUCCESSFULLY!`n" | Out-File -FilePath $outfileName -Append 
    write-output $ARNtoAdd | Out-File -FilePath $outfileName -Append 
}

# test API Connection
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"

Write-host "`nTesting API Connection...`n" 
Write-Output "`nTesting API Connection...`n" | Out-File -FilePath $outfileName -Append 
$headers.Add("apiKey", "$apiKey")
$apiTest = Invoke-RestMethod 'https://helios.cohesity.com/irisservices/api/v1/public/mcm/clusters/info' -Method 'GET' -Headers $headers 

if(!$apiTest){
    write-host "`nInvalid API Key" -ForegroundColor Yellow 
    write-output "`nInvalid API Key" | Out-File -FilePath $outfileName -Append 
    exit
}else{
    Write-Host "`nConnection with API Key SUCCESSFUL!`n" -ForegroundColor Green 
    write-output "`nConnection with API Key SUCCESSFUL!`n" | Out-File -FilePath $outfileName -Append 
    write-output $apiTest | Out-File -FilePath $outfileName -Append 
}

# validate DMaaS Tenant ID
Write-host "`nValidating Tenant ID...`n"  
write-output "`nValidating Tenant ID...`n" | Out-File -FilePath $outfileName -Append 
$headers.Add("accept", "application/json, text/plain, */*")
#$headers.Add('content-type: application/json')
$tenant = Invoke-RestMethod 'https://helios.cohesity.com/irisservices/api/v1/mcm/userInfo' -Method 'GET' -Headers $headers

$tenantId = $tenant.user.profiles.tenantId 
Write-host "`nTenant ID: $tenantId" -ForegroundColor Green 
write-output "`nTenant ID: $tenantId" | Out-File -FilePath $outfileName -Append 


# validate DMaaS Region ID
Write-host "`nValidating Region ID...`n" 
write-output "`nValidating Region ID...`n" | Out-File -FilePath $outfileName -Append 
$region = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/dms/tenants/regions?tenantId=$tenantId" -Method 'GET' -Headers $headers

foreach($regionIds in $region){

    $regionIds = $region.tenantRegionInfoList.regionId

    $compareRegion = Compare-Object -IncludeEqual -ReferenceObject $regionIds -DifferenceObject $regionId -ExcludeDifferent

    if(!$compareRegion){
        write-host "`nThere are no matching Region Ids asssociated with the confirmed Tenant ID." -ForegroundColor Yellow 
        write-output "`nThere are no matching Region Ids asssociated with the confirmed Tenant ID." | Out-File -FilePath $outfileName -Append 
        exit
    }else{
        Write-Host "`nRegion ID: $regionId" -ForegroundColor Green
        write-output "`nRegion ID: $regionId" | Out-File -FilePath $outfileName -Append 
    }

}


# first portion of AWS Registration
$headers.Add("regionId", "$regionId")

foreach($AWSaccount in $AWStoAdd){

    Write-Host "`nPreparing Registration of AWS ID: " $AWSaccount
    write-output "`nPreparing Registration of AWS ID: " $AWSaccount | Out-File -FilePath $outfileName -Append

    # $body = "{
    # `n    `"useCases`": [
    # `n        `"EC2`", 
    # `n        `"RDS`"
    # `n    ],
    # `n    `"tenantId`": `"$tenantId`",
    # `n    `"destinationRegionId`": `"$regionId`",
    # `n    `"awsAccountNumber`": `"$AWSid`"
    # `n}"

    $body = @{
        "useCases" = @(
            "EC2";
            "RDS"
        );        
        "tenantId" = "$tenantId";
        "destinationRegionId" = "$regionId";
        "awsAccountNumber" = "$AWSaccount"
    }


    if($AWSaccount){

        Write-Host "`nSTEP 1 - Registering AWS Account ID $AWSaccount in DMaaS...`n" 
        write-output "`nSTEP 1 - Registering AWS Account ID $AWSaccount in DMaaS...`n" | Out-File -FilePath $outfileName -Append 

        # prepare body of REST API Call
        $bodyJson = $body | ConvertTo-Json 
        write-host "$bodyJson"  
        write-output "$bodyJson" | Out-File -FilePath $outfileName -Append  
        $bodyJson = ConvertTo-Json -Compress -Depth 99 $body 

        # register DMaaS AWS Account - STEP 1
        $response = Invoke-RestMethod 'https://helios.cohesity.com/v2/mcm/dms/tenants/regions/aws-cloud-source' -Method 'POST' -Headers $headers -Body $bodyJson -ContentType 'application/json' 
        $response | ConvertTo-Json
        # Write-host "$response" -ForegroundColor Green 
        write-output "$response" | Out-File -FilePath $outfileName -Append

        # write the response CFT to file
        $awsCFTfile = "$awsCFT\$AWSaccount-$dateString.cft"
        write-output "$response" | Out-File -FilePath $awsCFTfile -force 

        # edit CFT file to remove api response data
        $cftJSON = Get-Content -path $awsCFTfile
        
        $cftJSON_first = $cftJSON[1..($cftJSON.count - 1)]
        $cftJSON = $cftJSON_first

        $cftJSON_second = $cftJSON[0..($cftJSON.count - 2)]
        $cftJSON = $cftJSON_second

        $awsCFTjson = "$awsCFT\$AWSaccount-$dateString.json"
        Write-Output "$cftJSON" | Set-Content -path $awsCFTjson  
        # Write-Output "$cftJSON" | out-file -filepath $awsCFTjson -force 
        "{" + (Get-Content $awsCFTjson | Out-String) | Set-Content $awsCFTjson
        $cftJSON = Get-Content -path $awsCFTjson
        write-host "Step 1 of DMaaS AWS Account Registration completed SUCCESSFULLY!" -ForegroundColor Green
        write-host "CFT Template Body: $cftJSON"
        write-host "CFT Template Location: $awsCFTjson"

        }

    else{
        Write-Host "`nNo AWS Account ID available to Register!`n" -ForegroundColor Yellow 
        write-output "`nNo AWS Account ID available to Register!`n" | Out-File -FilePath $outfileName -Append 
    }

        
#---------------------------------------------------------------------------------------------------------------#

        # deploy the CFT Template against the AWS Account ID

        # Set-AWSCredentials -AccessKey AKIAIOSFODNN7EXAMPLE -SecretKey wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY -StoreAs MyMainUserProfile
        # Validate: Get-AWSCredential -ListProfileDetail
        # Initialize-AWSDefaults -ProfileName MyMainUserProfile -Region us-west-2
    
    foreach($awsARN in $ARNtoAdd){
        if($cftJSON){

            $awsCreds = Get-AWSCredential -ListProfileDetail
            $awsDefault = $awsCreds | where ProfileName -eq "default" 
            write-host "If you are getting AWS permissions errors, please reference the following section of the Cohesity DMaaS Guide: https://docs.cohesity.com/baas/data-protect/aws-account-requirements.htm?tocpath=Amazon%20Web%20Services%7C_____1#IAMUserPermissionstoExecuteCFT" -ForegroundColor Yellow
            write-output "If you are getting AWS permissions errors, please reference the following section of the Cohesity DMaaS Guide: https://docs.cohesity.com/baas/data-protect/aws-account-requirements.htm?tocpath=Amazon%20Web%20Services%7C_____1#IAMUserPermissionstoExecuteCFT" | Out-File -FilePath $outfileName -Append
            if($awsDefault){
                $creds = (Use-STSRole -RoleArn "$awsARN" -RoleSessionName "cohesityCFTdeployment").Credentials
                # need to provide credentials from an IAM User to call functions
                    # $creds.AccessKeyId
                    # $creds.SecretAccessKey
                    # $creds.SessionToken
                    # $creds.Expiration


                Set-DefaultAWSRegion -Region $regionId
                # Validate: Get-DefaultAWSRegion

                # New-CFNStack - https://docs.aws.amazon.com/powershell/latest/reference/items/New-CFNStack.html

                $cfnStack = New-CFNStack -StackName cohesity-dmaas -TemplateBody "$cftJSON" -Capability "CAPABILITY_NAMED_IAM"
                write-output "$cfnStack" | Out-File -FilePath $outfileName -Append

                # monitor AWS CFT Template deployment
                $cftStatus = Get-CFNStack -StackName cohesity-dmaas 
                $cftStatus = $cftStatus.StackStatus
                    while($cftStatus -ne "CREATE_COMPLETE"){
                        $cftStatus = Get-CFNStack -StackName cohesity-dmaas
                        $cftStatus = $cftStatus.StackStatus
                        sleep 15
                        write-host "Cohesity-DMaaS AWS CFT Stack Deployment Status: $cftStatus" -ForegroundColor Yellow 
                        write-output "Cohesity-DMaaS AWS CFT Stack Deployment Status: $cftStatus"| Out-File -FilePath $outfileName -Append 
                    }

                    write-host "Cohesity-DMaaS AWS CFT Stack Deployment Status: $cftStatus" -ForegroundColor Green 
                    write-output "Cohesity-DMaaS AWS CFT Stack Deployment Status: $cftStatus"| Out-File -FilePath $outfileName -Append 
                }

            else{
                Write-Host "`nNo CFT created to deploy!`n" -ForegroundColor Yellow 
                write-output "`nNo CFT created to deploy!`n" | Out-File -FilePath $outfileName -Append 
            }
        }
    }


#---------------------------------------------------------------------------------------------------------------#

        # validate CloudFormation Stack Output

    if($cftStatus -eq "CREATE_COMPLETE"){
        Write-Host "`nValidating Registration of AWS Account ID $AWSaccount in DMaaS...`n" 
        write-output "`nValidating Registration of AWS Account ID $AWSaccount in DMaaS...`n" | Out-File -FilePath $outfileName -Append 

        # validate STEP 1 and successful CFT Deployment
        $validation = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/dms/tenants/regions/aws-cloud-source-verify?tenantId=$tenantId&destinationRegionId=$regionId&awsAccountNumber=$AWSaccount" -Method 'GET' -Headers $headers
        $validation | ConvertTo-Json 
        Write-host "$validation" -ForegroundColor Green
        write-output "$validation" | Out-File -FilePath $outfileName -Append
        }

    else {
        Write-Host "`nCFT did NOT deploy successfully!`n" -ForegroundColor Yellow 
        write-output "`nCFT did NOT deploy successfully!`n" | Out-File -FilePath $outfileName -Append 
    }

#---------------------------------------------------------------------------------------------------------------#

        # fetch AWS ARN 

    if(!$validation){
        Write-Host "`nFetching AWS ARN associated with Registration of AWS Account ID $AWSaccount in DMaaS...`n" 
        write-output "`nFetching AWS ARN associated with Registration of AWS Account ID $AWSaccount in DMaaS...`n" | Out-File -FilePath $outfileName -Append 

        $fetch = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/dms/tenants/regions/aws-cloud-source?tenantId=$tenantId&destinationRegionId=$regionId&awsAccountNumber=$AWSaccount" -Method 'GET' -Headers $headers
        
        $fetch | ConvertTo-Json
        Write-host "$fetch" -ForegroundColor Green
        write-output "$fetch" | Out-File -FilePath $outfileName -Append

        # edit fetch response to pull AWS ARN's
        $iam_role_arn = $fetch | select -expandproperty awsIamRoleArn
        write-host "AWS awsIamRoleName: $iam_role_arn" -ForegroundColor Green
        write-output $iam_role_arn | out-file -filepath $outfileName -Append

        $cp_role_arn = $fetch | select -expandproperty tenantCpRoleArn
        write-host "AWS tenantCpRoleArn: $cp_role_arn" -ForegroundColor Green
        write-output $cp_role_arn | out-file -filepath $outfileName -Append
        }
    
    else{
        Write-Host "`nCould not validate deployment of CFT Template!`n" -ForegroundColor Yellow 
        write-output "`nCould not validate deployment of CFT Template!`n" | Out-File -FilePath $outfileName -Append 
    }

#---------------------------------------------------------------------------------------------------------------#

    # final portion of AWS Registration
    if($iam_role_arn){
        Write-Host "`nProcessing AWS ARN associated with Registration of AWS Account ID $AWSaccount in DMaaS...`n" 

        $finalBody = @{
            "environment" = "kAWS";
            "awsParams" = @{
                "subscriptionType" = "kAWSCommercial";
                "standardParams" = @{
                    "authMethodType" = "kUseIAMRole";
                    "iamRoleAwsCredentials" = @{
                        "iamRoleArn" = "$iam_role_arn";
                        "cpIamRoleArn" = "$cp_role_arn"
                    }
                }
            }
        }


        Write-Host "`nFinalizing Registration of AWS Account ID $AWSaccount in DMaaS...`n" 

        # prepare body of REST API Call
        $bodyJson = $finalBody | ConvertTo-Json 
        write-host "$bodyJson"  
        write-output "$bodyJson" | Out-File -FilePath $outfileName -Append  
        $bodyJson = ConvertTo-Json -Compress -Depth 99 $finalBody 

        $final = Invoke-RestMethod 'https://helios.cohesity.com/v2/mcm/data-protect/sources/registrations' -Method 'POST' -Headers $headers -Body $bodyJson -ContentType 'application/json' 
        $final | ConvertTo-Json
        Write-host "$final" -ForegroundColor Green
        write-output "$final" | Out-File -FilePath $outfileName -Append
                
        if($final){
            Write-host "`nRegistration of $AWSaccount SUCCESSFUL!`n" -ForegroundColor Green
            write-output "`nRegistration of $AWSaccount SUCCESSFUL!`n"  | Out-File -FilePath $outfileName -Append
            write-output "`nRegistration of $AWSaccount SUCCESSFUL!`n"  | Out-File -FilePath $finalOutput -Append
            write-output "$final" | out-file -filepath $finalOutput -Append
        }

        else{
            Write-host "`nRegistration of $AWSaccount UNSUCCESSFUL!`n" -ForegroundColor Red 
            write-output "`nRegistration of $AWSaccount UNSUCCESSFUL!`n"  | Out-File -FilePath $outfileName -Append
            write-output "`nRegistration of $AWSaccount UNSUCCESSFUL!`n"  | Out-File -FilePath $finalOutput -Append
        }

        }

    else{
        Write-Host "`nNo valid AWS ARN's retrieved!`n" -ForegroundColor Yellow 
        write-output "`nNo valid AWS ARN's retrieved!`n" | Out-File -FilePath $outfileName -Append 
    }
}
