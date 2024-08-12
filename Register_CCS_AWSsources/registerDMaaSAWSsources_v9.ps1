
# ./registerDMaaSAWSsources.ps1 -username helios@cohesity.com -apiKey #### -regionId us-east-1 -awsRegion us-east-2 -AWSid #### -roleARN "AWS_ARN"

# install PowerShell, if on macOS: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-macos?view=powershell-7.2
# upgrade PowerShell Module to current revision of 7.2.4: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.2#msi

# install AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html#getting-started-install-instructions
# install AWS CLI for Powershell: https://docs.aws.amazon.com/powershell/latest/userguide/pstools-getting-set-up-windows.html#ps-installing-awswindowspowershell

# process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apiKey,  # apiKey generated in DMaaS UI
    [Parameter(Mandatory = $True)][string]$userName,  # DMaaS username associated with apiKey
    [Parameter(Mandatory = $True)][string]$regionId,  # DMaaS region where AWS Account ID is to be Registered
    # [Parameter(Mandatory = $True)][string]$awsRegion,  # AWS region where AWS Account ID is Registered
    [Parameter(Mandatory = $True)][string]$awsCSV,  # directory path and filename of CSV (with first line: accountId,accountName,region)
    # [Parameter()][array]$AWSid,  # (optional) one or more AWS Account ID's (comma separated)
    # [Parameter()][string]$AWSlist = '',  # (optional) text file of AWS Account ID's (one per line)
    #     # it is MANDATORY that you use one of either AWSid or AWSlist (or both can be used, if needed)
    [Parameter()][array]$roleARN,  # (optional) AWS IAM ARN associated with CFT Deployment IAM Roles (comma separated)
    [Parameter()][string]$ARNlist = ''  # (optional) text file of AWS IAM ARN's associated with CFT Deployment IAM Roles (one per line)
        # it is MANDATORY that you use one of either roleARN or ARNlist (or both can be used, if needed), UNLESS using -awsLogin switch and then neither of these variables should be used
    # [Parameter()][switch]$awsLogin  # (optional) call switch if using AWS Credentials instead of assuming AWS Role
)

# set static variables
$dateString = (get-date).ToString('yyyy-MM-dd')
$dateTime = Get-Date -Format "dddd MM/dd/yyyy HH:mm"
$outfileName = "$PSScriptRoot\log-registerDMaasAWS-$dateString.txt"

# logging
function info_log{
    param ($statement)
    
    Write-Host "INFO    $statement" -ForegroundColor Blue
    Write-Output "$dateTime    INFO    $statement" | Out-File -FilePath $outfileName -Append
}

function warn_log{
    param ($statement)
    
    Write-Host "WARN    $statement" -ForegroundColor Yellow
    Write-Output "$dateTime    WARN    $statement" | Out-File -FilePath $outfileName -Append
}

function fail_log{
    param ($statement)
    
    Write-Host "FAIL    $statement" -ForegroundColor Red
    Write-Output "$dateTime    FAIL    $statement" | Out-File -FilePath $outfileName -Append
}

function pass_log{
    param ($statement)
    
    Write-Host "PASS    $statement" -ForegroundColor Green
    Write-Output "$dateTime    PASS    $statement" | Out-File -FilePath $outfileName -Append
}

# create CFT folder
$cftFolder = "CFT"
if (Test-Path $PSScriptRoot\$cftFolder) {
    pass_log "CFT Folder already exists."
}
else {

    #PowerShell Create directory if not exists
    New-Item $cftFolder -ItemType Directory
    pass_log "CFT Folder Created SUCCESSFULLY!"
}

$awsCFT = "$PSScriptRoot\$cftFolder"


# ensure the environment meets the PowerShell Module requirements of 5.1 or above 
info_log "Validating PowerShell Version..."
$version = $PSVersionTable.PSVersion
if($version.major -lt 5.1){
    fail_log "Please upgrade the PowerShell Module to the current revision of 7.2.4 by downloading from the Microsoft site: `nhttps://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.2#msi" 
    exit
}
else {
    pass_log "PowerShell Module is up to date." 
}

info_log "Validating AWS CLI PowerShell Module Installed..."
$modules = Get-Module -ListAvailable
$awsPS = $modules | Where-Object Name -eq "AWSPowerShell" 

if(!$awsPS){
    fail_log "Please install the AWSPowerShell Module to integrate the AWS CLI with PowerShell. To install this Module, please run: `nFind-Module -Name AWSPowerShell | Install-Module Reference Documentation: https://docs.aws.amazon.com/powershell/latest/userguide/pstools-getting-set-up-windows.html#ps-installing-awswindowspowershell" 
    exit
}
else {
    pass_log "PowerShell Module is up to date." 
}

# # gather list of AWS ID's to Register
# $AWStoAdd = @()
# foreach($AWS in $AWSid){
#     $AWStoAdd += $AWS
# }
# if ('' -ne $AWSlist){
#     if(Test-Path -Path $AWSlist -PathType Leaf){
#         $AWSid = Get-Content $AWSlist
#         foreach($AWS in $AWSid){
#             $AWStoAdd += [string]$AWS
#         }
#     }else{
#         Write-Host "AWS ID list file $AWSlist not found at specified directory!" -ForegroundColor Yellow 
#         Write-Output "$dateTime    WARN    AWS ID list directory $AWSlist not found at specified directory!" | Out-File -FilePath $outfileName -Append 
#         exit
#     }
# }

# $AWStoAdd = @($AWStoAdd | Where-Object {$_ -ne ''})

# if($AWStoAdd.Count -eq 0){
#     Write-Host "No AWS ID's specified!" -ForegroundColor Yellow  
#     Write-Output "$dateTime    WARN    No AWS ID's specified!" | Out-File -FilePath $outfileName -Append 
#     exit
# }else{
#     Write-Host "AWS ID's parsed SUCCESSFULLY!" -ForegroundColor Green 
#     Write-Output "$dateTime    INFO    AWS ID's parsed SUCCESSFULLY!" | Out-File -FilePath $outfileName -Append 
#     write-output $AWStoAdd | Out-File -FilePath $outfileName -Append 
# }

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
        fail_log "AWS ARN list file $ARNlist not found at specified directory!"
        exit
    }
}

$ARNtoAdd = @($ARNtoAdd | Where-Object {$_ -ne ''})

if($ARNtoAdd.Count -eq 0){
    fail_log "No AWS IAM ARN's specified!" 
    exit
}else{
    pass_log "AWS IAM ARN's parsed SUCCESSFULLY!" 
    info_log $ARNtoAdd | Out-File -FilePath $outfileName -Append 
}


# functions
function errorOutput {
    param (
        [string]$Message
    )
    fail_log "Error: $Message"
    exit 1
}

function Invoke-AWSCommand {
    param (
        [string]$Command
    )
    $awsOutput = Invoke-Expression $Command 2>&1
    if ($LASTEXITCODE -ne 0) {
        errorOutput "AWS command failed: $awsOutput"
    }
    return $awsOutput
}

# source the cohesity-api helper code
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)

# connect to Helios
apiauth -vip "helios.cohesity.com" -username $userName -password $apiKey -regionId $regionId


# test API Connection
# Write-host "Testing API Connection..." 
# Write-Output "$dateTime    INFO    Testing API Connection..." | Out-File -FilePath $outfileName -Append 
# $apiTest = api get -mcm "/clusters/info" 

# if(!$apiTest){
#     write-host "Invalid API Key" -ForegroundColor Yellow 
#     write-output "$dateTime    WARN    Invalid API Key" | Out-File -FilePath $outfileName -Append 
#     exit
# }else{
#     Write-Host "Connection with apiKey SUCCESSFUL!" -ForegroundColor Green 
#     write-output "$dateTime    INFO    Connection with apiKey SUCCESSFUL!" | Out-File -FilePath $outfileName -Append 
#     write-output $apiTest | Out-File -FilePath $outfileName -Append 
# }

# validate DMaaS Tenant ID
info_log "Validating Tenant ID..."  

$sessionUser = api get sessionUser
$tenantId = $sessionUser.tenantId

if(!$tenantId){
    warn_log "No DMaaS Tenant ID found!"
}
else{
    pass_log "Tenant ID: $tenantId" 
}

# # validate DMaaS Region ID
# Write-host "Validating DMaaS Region ID..." 
# write-output "$dateTime    INFO    Validating DMaaS Region ID..." | Out-File -FilePath $outfileName -Append 
# $region = api get -mcmv2 dms/tenants/regions?tenantId=$tenantId
# $regions = $region.tenantRegionInfoList.regionId

# $compareRegion = Compare-Object -IncludeEqual -ReferenceObject $regions -DifferenceObject $regionId -ExcludeDifferent
# $verRegion = $compareRegion.InputObject | where-object{$compareRegion.SideIndicator -eq "=="}

# if($verRegion){
#     Write-Host "DMaaS Region ID Verified: $verRegion" -ForegroundColor Green
#     write-output "$dateTime    INFO    DMaaS Region ID Verified: $verRegion" | Out-File -FilePath $outfileName -Append 
# }
# else{
#     write-host "There are no matching DMaaS Region Ids asssociated with the specified Tenant ID!" -ForegroundColor Yellow 
#     write-output "$dateTime    WARN    There are no matching DMaaS Region Ids asssociated with the specified Tenant ID!" | Out-File -FilePath $outfileName -Append 
#     exit
# }

# clear AWS Credential Stores
# $awsCredStores = Get-AWSCredentials -ListStoredCredentials
# foreach($awsCredStore in $awsCredStores) {
#     Remove-AWSCredentialProfile -ProfileName $awsCredStore
# }

# Get the list of AWS CLI profiles
$awsProfiles = Invoke-AWSCommand "aws configure list-profiles"
        
# Process the awsCSV CSV file
$awsData = Import-Csv $awsCSV 
    foreach ($row in $awsData) {
    $AWSaccount = $row.accountId
    $AWSname = $row.accountName
    $AWSregion= $row.region

    # first portion of AWS Registration
    info_log "Preparing DMaaS Registration of AWS Account: " $AWSname

    $awsPayload = @{
        "useCases" = @(
            "EC2";
            "RDS"
        );        
        "tenantId" = "$tenantId";
        "destinationRegionId" = "$regionId";
        "awsAccountNumber" = "$AWSaccount"
    }


    if($AWSaccount){

        info_log "STEP 1 - Registering AWS Account ID $AWSaccount in DMaaS..." 

        # prepare body of REST API Call
        $bodyJson = $awsPayload | ConvertTo-Json 
        info_log "STEP 1 DMaaS AWS Accout Registration API Payload: `n$bodyJson"  
        $bodyJson = ConvertTo-Json -Compress -Depth 99 $body 

        # register DMaaS AWS Account - STEP 1
        $response = api post -mcmv2 "/dms/tenants/regions/aws-cloud-source?tenantId=$tenandId&destinationRegionId=$regionId&awsAccountNumber=$AWSaccount"
        $response | ConvertTo-Json
        # Write-host "$response" -ForegroundColor Green 
        pass_log "Response from STEP 1 DMaaS AWS Accout Registration API: `n$response"

        # write the response CFT to file
        $awsCFTfile = "$awsCFT\$AWSaccount-$dateString.cft"
        pass_log "$response" | Out-File -FilePath $awsCFTfile -force 

        # edit CFT file to remove api response data
        info_log "STEP 2 - Editing API Output to create CloudFormation Template for AWS Account ID $AWSaccount..." 

        $cftJSON = Get-Content -path $awsCFTfile
        
        # removing first line of text from API response
            # example of text being removed: @{awsAccountNumber=XXXXXX; awsIamRoleArn=arn:aws:iam::XXXXXX:role/cohesity-aws-cloud-source-us-east-1-XXXXXX; awsIamRoleName=cohesity-aws-cloud-source-us-east-1-XXXXXX; cloudFormationTemplate={
        $cftJSON_first = $cftJSON[1..($cftJSON.count - 1)]
        $cftJSON = $cftJSON_first

        # removing last line of text from API response
            # example of text being removed: ; cloudFormationTemplateUrl=https://console.aws.amazon.com//cloudformation/home#/stacks/create/review?templateURL=https://cohesity-source-registration.s3.us-east-2.amazonaws.com/hp1/XXXXXX-XXXXXX/cohesity-cft-XXXXXX.json; destinationRegionId=us-east-1; tenantCpRoleArn=arn:aws:iam::XXXXXX:role/c-cp-r-acs-XXXXXX-XXXXXX-XXXXXX; tenantId=XXXXXX:XXXXXX/; useCases=System.Object[]}
        $cftJSON_second = $cftJSON[0..($cftJSON.count - 2)]
        $cftJSON = $cftJSON_second

        $awsCFTjson = "$awsCFT\$AWSaccount-$dateString.json"
        Write-Output "$cftJSON" | Set-Content -path $awsCFTjson  
        # Write-Output "$cftJSON" | out-file -filepath $awsCFTjson -force 
        "{" + (Get-Content $awsCFTjson | Out-String) | Set-Content $awsCFTjson
        $cftJSON = Get-Content -path $awsCFTjson
        info_log "Step 1 of DMaaS AWS Account Registration completed SUCCESSFULLY!" 
        info_log "CFT Template Body: $cftJSON"
        info_log "CFT Template Location: $awsCFTjson"
        }

    else{
        warn_log "No AWS Account ID available to Register!"
    }

        
#---------------------------------------------------------------------------------------------------------------#

    # deploy the CFT Template against the AWS Account ID

    # Set-AWSCredentials -AccessKey xxxxxx -SecretKey xxxxxxx -StoreAs MyMainUserProfile
    # Validate: Get-AWSCredential -ListProfileDetail
    # Initialize-AWSDefaultConfiguration -ProfileName MyMainUserProfile -Region us-west-2

    info_log "STEP 3 - Deploying CloudFormation Template in AWS Account ID $AWSaccount..." 

    $awsProfile = $null
        
    # Find the profile that matches the account ID
    foreach ($profile in $awsProfiles) {
        if ($profile -like "*$AWSaccount*") {
            # clear AWS Credential Stores
            Remove-AWSCredentialProfile -ProfileName $profile
            $awsProfile = $profile
            break
        }
    }

    if ($null -eq $awsProfile) {
        errorOutput "No matching profile found for account ID $AWSaccount"
    }

    # Set AWS CLI to use the profile and region
    $env:AWS_PROFILE = $awsProfile
    $env:AWS_DEFAULT_REGION = $AWSregion
    Get-AWSCredential -ListProfileDetail
    Initialize-AWSDefaultConfiguration -ProfileName MyMainUserProfile -Region $AWSregion
    Set-AWSCredentials -ProfileName $awsProfile

    info_log "Current AWS Profile: $awsProfile" 
    
    if($cftJSON){ 

        # if($awsLogin -eq $true){
        #     $AccessKey = read-host -prompt "Please input the AWS Account AccessKey associated with Account ID $AWSaccount : "
        #     $SecretKey = read-host -prompt "Please input the AWS Account SecretKey associated with Account ID $AWSaccount : "
        #     $UserProfile = read-host -prompt "Please input storeAs Profile Name associated with AWS Account ID $AWSaccount : "
    
        #     Set-AWSCredentials -AccessKey $AccessKey -SecretKey $SecretKey -StoreAs $UserProfile
        #     Initialize-AWSDefaultConfiguration -ProfileName $UserProfile -Region $awsRegion
        #     Set-AWSCredentials -ProfileName $UserProfile 
        # }
        # else{
        #     foreach($awsARN in $ARNtoAdd){
                        
        #         if($awsCreds){
        #             $creds = (Use-STSRole -RoleArn "$awsARN" -RoleSessionName "cohesityCFTdeployment").Credentials
        #             # need to provide credentials from an IAM User to call functions
        #                 # $creds.AccessKeyId
        #                 # $creds.SecretAccessKey
        #                 # $creds.SessionToken
        #                 # $creds.Expiration

        #         }

        #         else{
        #             Write-Host "No AWS Credentials initialized on this box! If you are experiencing AWS permissions errors, please reference the following section of the Cohesity DMaaS Guide: https://docs.cohesity.com/baas/data-protect/aws-account-requirements.htm?tocpath=Amazon%20Web%20Services%7C_____1#IAMUserPermissionstoExecuteCFT" -ForegroundColor Yellow 
        #             write-output "$dateTime    WARN    No AWS Credentials initialized on this box! If you are experiencing AWS permissions errors, please reference the following section of the Cohesity DMaaS Guide: https://docs.cohesity.com/baas/data-protect/aws-account-requirements.htm?tocpath=Amazon%20Web%20Services%7C_____1#IAMUserPermissionstoExecuteCFT" | Out-File -FilePath $outfileName -Append
        #         }
        #     }
        # }
        #         Set-DefaultAWSRegion -Region $awsRegion
                # Validate: Get-DefaultAWSRegion

                # New-CFNStack - https://docs.aws.amazon.com/powershell/latest/reference/items/New-CFNStack.html

        $cfnStack = New-CFNStack -StackName cohesity-dmaas -TemplateBody "$cftJSON" -Capability "CAPABILITY_NAMED_IAM"
        pass_log "Response from AWS CFT Deployment API: $cfnStack" 

        # monitor AWS CFT Template deployment
        $cftStatus = Get-CFNStack -StackName cohesity-dmaas 
        $cftStatus = $cftStatus.StackStatus
            while($cftStatus -ne "CREATE_COMPLETE"){
                $cftStatus = Get-CFNStack -StackName cohesity-dmaas
                $cftStatus = $cftStatus.StackStatus
                sleep 15
                warn_log "Cohesity-DMaaS AWS CFT Stack Deployment Status: $cftStatus" 

                if($cftStatus -eq "ROLLBACK_COMPLETE"){
                    warn_log "CFT Template Deployment FAILED! Please reference the Events section on the AWS CFT Template webpage for further details." 

                    # output CFT Creation Events
                    $stackEvents = Get-CFNStackEvent -StackName "cohesity-dmaas" -Region $awsRegion
                    warn_log "'cohesity-dmaas' AWS CFT Stack Creation Events: $stackEvents" 
                }
            }

            pass_log "Cohesity-DMaaS AWS CFT Stack Deployment Status: $cftStatus"

            # output CFT Creation Events
            $stackEvents = Get-CFNStackEvent -StackName "cohesity-dmaas" -Region $awsRegion
            pass_log "'cohesity-dmaas' AWS CFT Stack Creation Events: $stackEvents"
    }
    else{
        warn_log "No CFT created to deploy!"
        }

    #---------------------------------------------------------------------------------------------------------------#
        
    
    foreach($awsARN in $ARNtoAdd){
        if($cftJSON){             
            if($awsCreds){
                $creds = (Use-STSRole -RoleArn "$awsARN" -RoleSessionName "cohesityCFTdeployment").Credentials
                # need to provide credentials from an IAM User to call functions
                    # $creds.AccessKeyId
                    # $creds.SecretAccessKey
                    # $creds.SessionToken
                    # $creds.Expiration

                # Set-DefaultAWSRegion -Region $awsregion
                # Validate: Get-DefaultAWSRegion

                # New-CFNStack - https://docs.aws.amazon.com/powershell/latest/reference/items/New-CFNStack.html

                $cfnStack = New-CFNStack -StackName cohesity-dmaas -TemplateBody "$cftJSON" -Capability "CAPABILITY_NAMED_IAM"
                info_log "Response from AWS CFT Deployment API: $cfnStack"

                # monitor AWS CFT Template deployment
                $cftStatus = Get-CFNStack -StackName cohesity-dmaas 
                $cftStatus = $cftStatus.StackStatus
                    while($cftStatus -ne "CREATE_COMPLETE"){
                        $cftStatus = Get-CFNStack -StackName cohesity-dmaas
                        $cftStatus = $cftStatus.StackStatus
                        sleep 15
                        warn_log "Cohesity-DMaaS AWS CFT Stack Deployment Status: $cftStatus" 

                        if($cftStatus -eq "ROLLBACK_COMPLETE"){
                            warn_log "CFT Template Deployment FAILED! Please reference the Events section on the AWS CFT Template webpage for further details." 
                        }
                    }

                    pass_log "Cohesity-DMaaS AWS CFT Stack Deployment Status: $cftStatus" 
                }

            else{
                warn_log "No Default AWS Credentials initialized on this box! If you are experiencing AWS permissions errors, please reference the following section of the Cohesity DMaaS Guide: `nhttps://docs.cohesity.com/baas/data-protect/aws-account-requirements.htm?tocpath=Amazon%20Web%20Services%7C_____1#IAMUserPermissionstoExecuteCFT" 
            }
        }
        else{
            warn_log "No CFT created to deploy!" 
        }
    }

#---------------------------------------------------------------------------------------------------------------#

    # validate CloudFormation Stack Output

    if($cftStatus -eq "CREATE_COMPLETE"){
        info_log "STEP 4 - Validating DMaaS can communicate to AWS Account ID $AWSaccount using CFT Template Roles..." 

        # validate STEP 1 and successful CFT Deployment
        $validation = api get -mcmv2 "dms/tenants/regions/aws-cloud-source-verify?tenantId=$tenantId&destinationRegionId=$regionId&awsAccountNumber=$AWSaccount"
        $validation | ConvertTo-Json 
        pass_log "Response from DMaaS CFT Deployment Validation API: $validation"
        }

    else {
        warn_log "CFT did NOT deploy successfully!"
    }

#---------------------------------------------------------------------------------------------------------------#

        # fetch AWS ARN 

    if(!$validation){
        info_log "STEP 5 - Fetching AWS IAM ARN associated with Registration of AWS Account ID $AWSaccount in DMaaS..." 

        $fetch = api get -mcmv2 "dms/tenants/regions/aws-cloud-source?tenantId=$tenantId&destinationRegionId=$regionId&awsAccountNumber=$AWSaccount"
        
        $fetch | ConvertTo-Json
        pass_log "Response from Fetch ARN's API: $fetch" 

        # edit fetch response to pull AWS IAM ARN's
        $iam_role_arn = $fetch | select-object -expandproperty awsIamRoleArn
        pass_log "AWS awsIamRoleName: $iam_role_arn"

        $cp_role_arn = $fetch | select-object -expandproperty tenantCpRoleArn
        pass_log "AWS tenantCpRoleArn: $cp_role_arn" 
        }
    
    else{
        warn_log "Could not validate deployment of CFT Template!" 
    }

#---------------------------------------------------------------------------------------------------------------#

    # final portion of AWS Registration
    if($iam_role_arn){
        info_log "Processing AWS IAM ARN associated with Registration of AWS Account ID $AWSaccount in DMaaS..." 

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
        info_log "STEP 6 -Finalizing Registration of AWS Account ID $AWSaccount in DMaaS..." 

        # prepare body of REST API Call
        # $bodyJson = $finalBody | ConvertTo-Json 
        info_log "Final AWS Registration API Payload: $finalBody"   
        # $bodyJson = ConvertTo-Json -Compress -Depth 99 $finalBody 

        $final = api post -mcmv2 "data-protect/sources/registrations" $finalBody 
        $final | ConvertTo-Json
        pass_log "Response from Final AWS Registration API: $final" 
                
        if($final){
            pass_log "Registration of $AWSaccount SUCCESSFUL!" -ForegroundColor Green
            pass_log "$final"
        }
        else{
            fail_log "Registration of $AWSaccount UNSUCCESSFUL!"
        }
    }
    else{
        warn_log "No valid AWS IAM ARN's retrieved!" 
    }
}
