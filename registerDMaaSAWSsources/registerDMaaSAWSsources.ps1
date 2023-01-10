
# ./registerDMaaSAWSsources.ps1 -apiKey #### -regionId us-east-1 -awsRegion us-east-2 -AWSid #### -roleARN "AWS_ARN"

# install PowerShell, if on macOS: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-macos?view=powershell-7.2
# upgrade PowerShell Module to current revision of 7.2.4: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.2#msi

# install AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html#getting-started-install-instructions
# install AWS CLI for Powershell: https://docs.aws.amazon.com/powershell/latest/userguide/pstools-getting-set-up-windows.html#ps-installing-awswindowspowershell

# process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apiKey,  # apiKey generated in DMaaS UI
    [Parameter(Mandatory = $True)][string]$regionId,  # DMaaS region where AWS Account ID is to be Registered
    [Parameter(Mandatory = $True)][string]$awsRegion,  # AWS region where AWS Account ID is Registered
    [Parameter()][array]$AWSid,  # (optional) one or more AWS Account ID's (comma separated)
    [Parameter()][string]$AWSlist = '',  # (optional) text file of AWS Account ID's (one per line)
        # it is MANDATORY that you use one of either AWSid or AWSlist (or both can be used, if needed)
    [Parameter()][array]$roleARN,  # (optional) AWS IAM ARN associated with CFT Deployment IAM Roles (comma separated)
    [Parameter()][string]$ARNlist = '',  # (optional) text file of AWS IAM ARN's associated with CFT Deployment IAM Roles (one per line)
        # it is MANDATORY that you use one of either roleARN or ARNlist (or both can be used, if needed), UNLESS using -awsLogin switch and then neither of these variables should be used
    [Parameter()][switch]$awsLogin  # (optional) call switch if using AWS Credentials instead of assuming AWS Role
)

# set static variables
$dateString = (get-date).ToString('yyyy-MM-dd')
$dateTime = Get-Date -Format "dddd MM/dd/yyyy HH:mm"
$outfileName = "$PSScriptRoot\log-registerDMaasAWS-$dateString.txt"
$finalOutput = "$PSScriptRoot\log-DMaaSAWSinfo-$dateString.txt"

# create CFT folder
$cftFolder = "CFT"

    if (Test-Path $PSScriptRoot\$cftFolder) {
    
        Write-Host "CFT Folder already exists."
        Write-Output "$dateTime    INFO    CFT Folder already exists." | Out-File -FilePath $outfileName -Append 
    }
    else {
    
        #PowerShell Create directory if not exists
        New-Item $cftFolder -ItemType Directory
        Write-Host "CFT Folder Created SUCCESSFULLY!" -ForegroundColor Green
        Write-Output "$dateTime    INFO    CFT Folder Created SUCCESSFULLY!" | Out-File -FilePath $outfileName -Append 
    }

    $awsCFT = "$PSScriptRoot\$cftFolder"

# ensure the environment meets the PowerShell Module requirements of 5.1 or above 

write-host "`nValidating PowerShell Version...`n"
Write-Output "`n$dateTime    INFO    Validating PowerShell Version...`n" | Out-File -FilePath $outfileName -Append
$version = $PSVersionTable.PSVersion
if($version.major -lt 5.1){
    write-host "`nPlease upgrade the PowerShell Module to the current revision of 7.2.4 by downloading from the Microsoft site: `nhttps://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.2#msi" 
    Write-Output "`n$dateTime    WARN    Please upgrade the PowerShell Module to the current revision of 7.2.4 by downloading from the Microsoft site: `nhttps://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.2#msi" | Out-File -FilePath $outfileName -Append
}
else {
    write-host "PowerShell Module is up to date." 
    Write-Output "$dateTime    INFO    PowerShell Module is up to date." | Out-File -FilePath $outfileName -Append
}


write-host "`nValidating AWS CLI PowerShell Module Installed...`n"
Write-Output "`n$dateTime    INFO    Validating AWS CLI PowerShell Module Installed...`n" | Out-File -FilePath $outfileName -Append
$modules = Get-Module -ListAvailable
$awsPS = $modules | Where-Object Name -eq "AWSPowerShell" 

if(!$awsPS){
    write-host "`nPlease install the AWSPowerShell Module to integrate the AWS CLI with PowerShell. To install this Module, please run: `nFind-Module -Name AWSPowerShell | Install-Module `n`nReference Documentation: `nhttps://docs.aws.amazon.com/powershell/latest/userguide/pstools-getting-set-up-windows.html#ps-installing-awswindowspowershell" 
    Write-Output "`n$dateTime    WARN    Please install the AWSPowerShell Module to integrate the AWS CLI with PowerShell. To install this Module, please run: `nFind-Module -Name AWSPowerShell | Install-Module `n`nReference Documentation: `nhttps://docs.aws.amazon.com/powershell/latest/userguide/pstools-getting-set-up-windows.html#ps-installing-awswindowspowershell"  | Out-File -FilePath $outfileName -Append
}
else {
    write-host "PowerShell Module is up to date." 
    Write-Output "$dateTime    INFO    AWS CLI PowerShell Module is installed." | Out-File -FilePath $outfileName -Append
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
        Write-Host "`nAWS ID list file $AWSlist not found at specified directory!" -ForegroundColor Yellow 
        Write-Output "`n$dateTime    WARN    AWS ID list directory $AWSlist not found at specified directory!" | Out-File -FilePath $outfileName -Append 
        exit
    }
}

$AWStoAdd = @($AWStoAdd | Where-Object {$_ -ne ''})

if($AWStoAdd.Count -eq 0){
    Write-Host "`nNo AWS ID's specified!" -ForegroundColor Yellow  
    Write-Output "`n$dateTime    WARN    No AWS ID's specified!" | Out-File -FilePath $outfileName -Append 
    exit
}else{
    Write-Host "`nAWS ID's parsed SUCCESSFULLY!`n" -ForegroundColor Green 
    Write-Output "`n$dateTime    INFO    AWS ID's parsed SUCCESSFULLY!`n" | Out-File -FilePath $outfileName -Append 
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
        Write-Host "`nAWS ARN list file $ARNlist not found at specified directory!" -ForegroundColor Yellow 
        Write-Output "`nA$dateTime    WARN    WS ARN list file $ARNlist not found at specified directory!" | Out-File -FilePath $outfileName -Append 
        exit
    }
}

$ARNtoAdd = @($ARNtoAdd | Where-Object {$_ -ne ''})

if($ARNtoAdd.Count -eq 0){
    Write-Host "`nNo AWS IAM ARN's specified!" -ForegroundColor Yellow  
    Write-Output "`n$dateTime    WARN    No AWS IAM ARN's specified!" | Out-File -FilePath $outfileName -Append 
    exit
}else{
    Write-Host "`nAWS IAM ARN's parsed SUCCESSFULLY!`n" -ForegroundColor Green 
    Write-Output "`n$dateTime    INFO    AWS IAM ARN's parsed SUCCESSFULLY!`n" | Out-File -FilePath $outfileName -Append 
    write-output $ARNtoAdd | Out-File -FilePath $outfileName -Append 
}

# test API Connection
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"

Write-host "`nTesting API Connection...`n" 
Write-Output "`n$dateTime    INFO    Testing API Connection...`n" | Out-File -FilePath $outfileName -Append 
$headers.Add("apiKey", "$apiKey")
$apiTest = Invoke-RestMethod 'https://helios.cohesity.com/irisservices/api/v1/public/mcm/clusters/info' -Method 'GET' -Headers $headers 

if(!$apiTest){
    write-host "`nInvalid API Key" -ForegroundColor Yellow 
    write-output "`n$dateTime    WARN    Invalid API Key" | Out-File -FilePath $outfileName -Append 
    exit
}else{
    Write-Host "`nConnection with apiKey SUCCESSFUL!`n" -ForegroundColor Green 
    write-output "`n$dateTime    INFO    Connection with apiKey SUCCESSFUL!`n" | Out-File -FilePath $outfileName -Append 
    write-output $apiTest | Out-File -FilePath $outfileName -Append 
}

# validate DMaaS Tenant ID
Write-host "`nValidating Tenant ID...`n"  
write-output "`n$dateTime    INFO    Validating Tenant ID...`n" | Out-File -FilePath $outfileName -Append 
$headers.Add("accept", "application/json, text/plain, */*")
#$headers.Add('content-type: application/json')
$tenant = Invoke-RestMethod 'https://helios.cohesity.com/irisservices/api/v1/mcm/userInfo' -Method 'GET' -Headers $headers

$tenantId = $tenant.user.profiles.tenantId 

if(!$tenantId){
    write-host "`nNo DMaaS Tenant ID found!" -ForegroundColor Yellow
    write-output "`n$dateTime    WARN    No DMaaS Tenant ID found!" | out-file -filepath $outfileName -Append
}
else{
    Write-host "`nTenant ID: $tenantId" -ForegroundColor Green 
    write-output "`n$dateTime    INFO    Tenant ID: $tenantId" | Out-File -FilePath $outfileName -Append 
}



# validate DMaaS Region ID
Write-host "`nValidating DMaaS Region ID...`n" 
write-output "`n$dateTime    INFO    Validating DMaaS Region ID...`n" | Out-File -FilePath $outfileName -Append 
$region = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/dms/tenants/regions?tenantId=$tenantId" -Method 'GET' -Headers $headers
$regions = $region.tenantRegionInfoList.regionId

$compareRegion = Compare-Object -IncludeEqual -ReferenceObject $regions -DifferenceObject $regionId -ExcludeDifferent
$verRegion = $compareRegion.InputObject | where-object{$compareRegion.SideIndicator -eq "=="}

if($verRegion){
    Write-Host "`nDMaaS Region ID Verified: $verRegion" -ForegroundColor Green
    write-output "`n$dateTime    INFO    DMaaS Region ID Verified: $verRegion`n" | Out-File -FilePath $outfileName -Append 
}
else{
    write-host "`nThere are no matching DMaaS Region Ids asssociated with the specified Tenant ID!" -ForegroundColor Yellow 
    write-output "`n$dateTime    WARN    There are no matching DMaaS Region Ids asssociated with the specified Tenant ID!" | Out-File -FilePath $outfileName -Append 
    exit
}


# first portion of AWS Registration
$headers.Add("regionId", "$regionId")

foreach($AWSaccount in $AWStoAdd){

    Write-Host "`nPreparing DMaaS Registration of AWS ID: " $AWSaccount
    write-output "`n$dateTime    INFO    Preparing DMaaS Registration of AWS ID: " $AWSaccount | Out-File -FilePath $outfileName -Append

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
        write-output "`n$dateTime    INFO    STEP 1 - Registering AWS Account ID $AWSaccount in DMaaS...`n" | Out-File -FilePath $outfileName -Append 

        # prepare body of REST API Call
        $bodyJson = $body | ConvertTo-Json 
        write-host "`nSTEP 1 DMaaS AWS Accout Registration API Payload: `n$bodyJson"  
        write-output "`n$dateTime    INFO    STEP 1 DMaaS AWS Accout Registration API Payload: `n$bodyJson" | Out-File -FilePath $outfileName -Append  
        $bodyJson = ConvertTo-Json -Compress -Depth 99 $body 

        # register DMaaS AWS Account - STEP 1
        $response = Invoke-RestMethod 'https://helios.cohesity.com/v2/mcm/dms/tenants/regions/aws-cloud-source' -Method 'POST' -Headers $headers -Body $bodyJson -ContentType 'application/json' 
        $response | ConvertTo-Json
        # Write-host "$response" -ForegroundColor Green 
        write-output "`n$dateTime    INFO    Response from STEP 1 DMaaS AWS Accout Registration API: `n$response" | Out-File -FilePath $outfileName -Append

        # write the response CFT to file
        $awsCFTfile = "$awsCFT\$AWSaccount-$dateString.cft"
        write-output "$response" | Out-File -FilePath $awsCFTfile -force 

        # edit CFT file to remove api response data
        Write-Host "`nSTEP 2 - Editing API Output to create CloudFormation Template for AWS Account ID $AWSaccount...`n" 
        write-output "`n$dateTime    INFO    STEP 2 - Editing API Output to create CloudFormation Template for AWS Account ID $AWSaccount...`n" | Out-File -FilePath $outfileName -Append 

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
        write-host "`nStep 1 of DMaaS AWS Account Registration completed SUCCESSFULLY!" -ForegroundColor Green
        write-host "CFT Template Body: `n$cftJSON"
        write-host "CFT Template Location: `n$awsCFTjson"
        write-output "`n$dateTime    INFO    Step 1 of DMaaS AWS Account Registration completed SUCCESSFULLY!" | Out-File -FilePath $outfileName
        write-output "`n$dateTime    INFO    CFT Template Body: `n$cftJSON" | Out-File -FilePath $outfileName
        write-output "`n$dateTime    INFO    CFT Template Location: `n$awsCFTjson" | Out-File -FilePath $outfileName

        }

    else{
        Write-Host "`nNo AWS Account ID available to Register!`n" -ForegroundColor Yellow 
        write-output "$dateTime    WARN    `nNo AWS Account ID available to Register!`n" | Out-File -FilePath $outfileName -Append 
    }

        
#---------------------------------------------------------------------------------------------------------------#

    # deploy the CFT Template against the AWS Account ID

    # Set-AWSCredentials -AccessKey xxxxxx -SecretKey xxxxxxx -StoreAs MyMainUserProfile
    # Validate: Get-AWSCredential -ListProfileDetail
    # Initialize-AWSDefaultConfiguration -ProfileName MyMainUserProfile -Region us-west-2

    Write-Host "`nSTEP 3 - Deploying CloudFormation Template in AWS Account ID $AWSaccount...`n" 
    write-output "`n$dateTime    INFO    STEP 3 - Deploying CloudFormation Template in AWS Account ID $AWSaccount...`n" | Out-File -FilePath $outfileName -Append 

    $awsCreds = Get-AWSCredential -ListProfileDetail

    Write-Host "`nCurrent AWS Credentials Set:`n$awsCreds" 
    write-output "`n$dateTime    INFO    Current AWS Credentials Set:`n$awsCreds`n" | Out-File -FilePath $outfileName -Append 
    
    if($cftJSON){ 
        if($awsLogin -eq $true){
            $AccessKey = read-host -prompt "Please input the AWS Account AccessKey associated with Account ID $AWSaccount : "
            $SecretKey = read-host -prompt "Please input the AWS Account SecretKey associated with Account ID $AWSaccount : "
            $UserProfile = read-host -prompt "Please input storeAs Profile Name associated with AWS Account ID $AWSaccount : "
    
            Set-AWSCredentials -AccessKey $AccessKey -SecretKey $SecretKey -StoreAs $UserProfile
            Initialize-AWSDefaultConfiguration -ProfileName $UserProfile -Region $awsRegion
            Set-AWSCredentials -ProfileName $UserProfile 
        }
        else{
            foreach($awsARN in $ARNtoAdd){
                        
                if($awsCreds){
                    $creds = (Use-STSRole -RoleArn "$awsARN" -RoleSessionName "cohesityCFTdeployment").Credentials
                    # need to provide credentials from an IAM User to call functions
                        # $creds.AccessKeyId
                        # $creds.SecretAccessKey
                        # $creds.SessionToken
                        # $creds.Expiration

                }

                else{
                    Write-Host "`nNo AWS Credentials initialized on this box! If you are experiencing AWS permissions errors, please reference the following section of the Cohesity DMaaS Guide: `nhttps://docs.cohesity.com/baas/data-protect/aws-account-requirements.htm?tocpath=Amazon%20Web%20Services%7C_____1#IAMUserPermissionstoExecuteCFT`n" -ForegroundColor Yellow 
                    write-output "`n$dateTime    WARN    No AWS Credentials initialized on this box! If you are experiencing AWS permissions errors, please reference the following section of the Cohesity DMaaS Guide: `nhttps://docs.cohesity.com/baas/data-protect/aws-account-requirements.htm?tocpath=Amazon%20Web%20Services%7C_____1#IAMUserPermissionstoExecuteCFT`n" | Out-File -FilePath $outfileName -Append
                }
            }
        }
                Set-DefaultAWSRegion -Region $awsRegion
                # Validate: Get-DefaultAWSRegion

                # New-CFNStack - https://docs.aws.amazon.com/powershell/latest/reference/items/New-CFNStack.html

                $cfnStack = New-CFNStack -StackName cohesity-dmaas -TemplateBody "$cftJSON" -Capability "CAPABILITY_NAMED_IAM"
                write-output "`n$dateTime    INFO    Response from AWS CFT Deployment API: `n$cfnStack" | Out-File -FilePath $outfileName -Append

                # monitor AWS CFT Template deployment
                $cftStatus = Get-CFNStack -StackName cohesity-dmaas 
                $cftStatus = $cftStatus.StackStatus
                    while($cftStatus -ne "CREATE_COMPLETE"){
                        $cftStatus = Get-CFNStack -StackName cohesity-dmaas
                        $cftStatus = $cftStatus.StackStatus
                        sleep 15
                        write-host "Cohesity-DMaaS AWS CFT Stack Deployment Status: $cftStatus" -ForegroundColor Yellow 
                        write-output "`n$dateTime    INFO    Cohesity-DMaaS AWS CFT Stack Deployment Status: $cftStatus" | Out-File -FilePath $outfileName -Append 

                        if($cftStatus -eq "ROLLBACK_COMPLETE"){
                            write-host "`nCFT Template Deployment FAILED! Please reference the Events section on the AWS CFT Template webpage for further details." -ForegroundColor Yellow
                            write-output "`n$dateTime    WARN    CFT Template Deployment FAILED! Please reference the Events section on the AWS CFT Template webpage for further details." | Out-File -FilePath $outfileName -Append 

                            # output CFT Creation Events
                            $stackEvents = Get-CFNStackEvent -StackName "cohesity-dmaas" -Region $awsRegion
                            Write-Host "`n'cohesity-dmaas' AWS CFT Stack Creation Events: `n$stackEvents`n" -ForegroundColor Yellow 
                            write-output "`n$dateTime    WARN    'cohesity-dmaas' AWS CFT Stack Creation Events: `n$stackEvents`n" | Out-File -FilePath $outfileName -Append

                        }
                    }

                    write-host "Cohesity-DMaaS AWS CFT Stack Deployment Status: $cftStatus" -ForegroundColor Green 
                    write-output "`n$dateTime    INFO    Cohesity-DMaaS AWS CFT Stack Deployment Status: $cftStatus"| Out-File -FilePath $outfileName -Append 

                    # output CFT Creation Events
                    $stackEvents = Get-CFNStackEvent -StackName "cohesity-dmaas" -Region $awsRegion
                    Write-Host "`n'cohesity-dmaas' AWS CFT Stack Creation Events: `n$stackEvents`n" -ForegroundColor Green 
                    write-output "`n$dateTime    INFO    'cohesity-dmaas' AWS CFT Stack Creation Events: `n$stackEvents`n" | Out-File -FilePath $outfileName -Append
    }
    else{
        Write-Host "`nNo CFT created to deploy!`n" -ForegroundColor Yellow 
        write-output "`n$dateTime    WARN    No CFT created to deploy!`n" | Out-File -FilePath $outfileName -Append
        }

    #---------------------------------------------------------------------------------------------------------------#
        
    
    # foreach($awsARN in $ARNtoAdd){
    #     if($cftJSON){             
    #         if($awsCreds){
    #             $creds = (Use-STSRole -RoleArn "$awsARN" -RoleSessionName "cohesityCFTdeployment").Credentials
    #             # need to provide credentials from an IAM User to call functions
    #                 # $creds.AccessKeyId
    #                 # $creds.SecretAccessKey
    #                 # $creds.SessionToken
    #                 # $creds.Expiration


    #             Set-DefaultAWSRegion -Region $regionId
    #             # Validate: Get-DefaultAWSRegion

    #             # New-CFNStack - https://docs.aws.amazon.com/powershell/latest/reference/items/New-CFNStack.html

    #             $cfnStack = New-CFNStack -StackName cohesity-dmaas -TemplateBody "$cftJSON" -Capability "CAPABILITY_NAMED_IAM"
    #             write-output "`n$dateTime    INFO    Response from AWS CFT Deployment API: `n$cfnStack" | Out-File -FilePath $outfileName -Append

    #             # monitor AWS CFT Template deployment
    #             $cftStatus = Get-CFNStack -StackName cohesity-dmaas 
    #             $cftStatus = $cftStatus.StackStatus
    #                 while($cftStatus -ne "CREATE_COMPLETE"){
    #                     $cftStatus = Get-CFNStack -StackName cohesity-dmaas
    #                     $cftStatus = $cftStatus.StackStatus
    #                     sleep 15
    #                     write-host "Cohesity-DMaaS AWS CFT Stack Deployment Status: $cftStatus" -ForegroundColor Yellow 
    #                     write-output "`n$dateTime    INFO    Cohesity-DMaaS AWS CFT Stack Deployment Status: $cftStatus" | Out-File -FilePath $outfileName -Append 

    #                     if($cftStatus -eq "ROLLBACK_COMPLETE"){
    #                         write-host "`nCFT Template Deployment FAILED! Please reference the Events section on the AWS CFT Template webpage for further details." -ForegroundColor Yellow
    #                         write-output "`n$dateTime    WARN    CFT Template Deployment FAILED! Please reference the Events section on the AWS CFT Template webpage for further details." | Out-File -FilePath $outfileName -Append 
    #                     }
    #                 }

    #                 write-host "Cohesity-DMaaS AWS CFT Stack Deployment Status: $cftStatus" -ForegroundColor Green 
    #                 write-output "`n$dateTime    INFO    Cohesity-DMaaS AWS CFT Stack Deployment Status: $cftStatus"| Out-File -FilePath $outfileName -Append 
    #             }

    #         else{
    #             Write-Host "`nNo Default AWS Credentials initialized on this box! If you are experiencing AWS permissions errors, please reference the following section of the Cohesity DMaaS Guide: `nhttps://docs.cohesity.com/baas/data-protect/aws-account-requirements.htm?tocpath=Amazon%20Web%20Services%7C_____1#IAMUserPermissionstoExecuteCFT`n" -ForegroundColor Yellow 
    #             write-output "`n$dateTime    WARN    No Default AWS Credentials initialized on this box! If you are experiencing AWS permissions errors, please reference the following section of the Cohesity DMaaS Guide: `nhttps://docs.cohesity.com/baas/data-protect/aws-account-requirements.htm?tocpath=Amazon%20Web%20Services%7C_____1#IAMUserPermissionstoExecuteCFT`n" | Out-File -FilePath $outfileName -Append
    #         }
    #     }
    #     else{
    #         Write-Host "`nNo CFT created to deploy!`n" -ForegroundColor Yellow 
    #         write-output "`n$dateTime    WARN    No CFT created to deploy!`n" | Out-File -FilePath $outfileName -Append
    #     }
    # }


#---------------------------------------------------------------------------------------------------------------#

    # validate CloudFormation Stack Output

    if($cftStatus -eq "CREATE_COMPLETE"){
        Write-Host "`nSTEP 4 - Validating DMaaS can communicate to AWS Account ID $AWSaccount using CFT Template Roles...`n" 
        write-output "`n$dateTime    INFO    STEP 4 - Validating DMaaS can communicate to AWS Account ID $AWSaccount using CFT Template Roles...`n" | Out-File -FilePath $outfileName -Append 

        # validate STEP 1 and successful CFT Deployment
        $validation = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/dms/tenants/regions/aws-cloud-source-verify?tenantId=$tenantId&destinationRegionId=$regionId&awsAccountNumber=$AWSaccount" -Method 'GET' -Headers $headers
        $validation | ConvertTo-Json 
        Write-host "Response from DMaaS CFT Deployment Validation API: `n$validation" -ForegroundColor Green
        write-output "`n$dateTime    INFO    Response from DMaaS CFT Deployment Validation API: `n$validation" | Out-File -FilePath $outfileName -Append
        }

    else {
        Write-Host "`nCFT did NOT deploy successfully!`n" -ForegroundColor Yellow 
        write-output "`n$dateTime    WARN    CFT did NOT deploy successfully!`n" | Out-File -FilePath $outfileName -Append 
    }

#---------------------------------------------------------------------------------------------------------------#

        # fetch AWS ARN 

    if(!$validation){
        Write-Host "`nSTEP 5 - Fetching AWS IAM ARN associated with Registration of AWS Account ID $AWSaccount in DMaaS...`n" 
        write-output "`n$dateTime    INFO    STEP 5 - Fetching AWS IAM ARN associated with Registration of AWS Account ID $AWSaccount in DMaaS...`n" | Out-File -FilePath $outfileName -Append 

        $fetch = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/dms/tenants/regions/aws-cloud-source?tenantId=$tenantId&destinationRegionId=$regionId&awsAccountNumber=$AWSaccount" -Method 'GET' -Headers $headers
        
        $fetch | ConvertTo-Json
        Write-host "Response from Fetch ARN's API: `n$fetch" -ForegroundColor Green
        write-output "`n$dateTime    INFO    Response from Fetch ARN's API: `n$fetch" | Out-File -FilePath $outfileName -Append

        # edit fetch response to pull AWS IAM ARN's
        $iam_role_arn = $fetch | select -expandproperty awsIamRoleArn
        write-host "AWS awsIamRoleName: $iam_role_arn" -ForegroundColor Green
        write-output "`n$dateTime    INFO    AWS awsIamRoleName: $iam_role_arn" | out-file -filepath $outfileName -Append

        $cp_role_arn = $fetch | select -expandproperty tenantCpRoleArn
        write-host "AWS tenantCpRoleArn: $cp_role_arn" -ForegroundColor Green
        write-output "`n$dateTime    INFO    AWS tenantCpRoleArn: $cp_role_arn" | out-file -filepath $outfileName -Append
        }
    
    else{
        Write-Host "`nCould not validate deployment of CFT Template!`n" -ForegroundColor Yellow 
        write-output "`n$dateTime    WARN    Could not validate deployment of CFT Template!`n" | Out-File -FilePath $outfileName -Append 
    }

#---------------------------------------------------------------------------------------------------------------#

    # final portion of AWS Registration
    if($iam_role_arn){
        Write-Host "`nProcessing AWS IAM ARN associated with Registration of AWS Account ID $AWSaccount in DMaaS...`n" 
        Write-output "`n$dateTime    INFO    Processing AWS IAM ARN associated with Registration of AWS Account ID $AWSaccount in DMaaS...`n" | Out-File -FilePath $outfileName -Append

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


        Write-Host "`nSTEP 6 -Finalizing Registration of AWS Account ID $AWSaccount in DMaaS...`n" 
        Write-output "`n$dateTime    INFO    STEP 6 - Finalizing Registration of AWS Account ID $AWSaccount in DMaaS...`n" | Out-File -FilePath $outfileName -Append

        # prepare body of REST API Call
        $bodyJson = $finalBody | ConvertTo-Json 
        write-host "Final AWS Registration API Payload: `n$bodyJson"  
        write-output "`n$dateTime    INFO    Final AWS Registration API Payload: `n$bodyJson" | Out-File -FilePath $outfileName -Append  
        $bodyJson = ConvertTo-Json -Compress -Depth 99 $finalBody 

        $final = Invoke-RestMethod 'https://helios.cohesity.com/v2/mcm/data-protect/sources/registrations' -Method 'POST' -Headers $headers -Body $bodyJson -ContentType 'application/json' 
        $final | ConvertTo-Json
        Write-host "Response from Final AWS Registration API: `n$final" -ForegroundColor Green
        write-output "`n$dateTime    INFO    Response from Final AWS Registration API: `n$final" | Out-File -FilePath $outfileName -Append
                
        if($final){
            Write-host "`nRegistration of $AWSaccount SUCCESSFUL!`n" -ForegroundColor Green
            write-output "`n$dateTime    INFO    Registration of $AWSaccount SUCCESSFUL!`n"  | Out-File -FilePath $outfileName -Append
            write-output "`n$dateTime    INFO    Registration of $AWSaccount SUCCESSFUL!`n"  | Out-File -FilePath $finalOutput -Append
            write-output "`n$dateTime    INFO    $final" | out-file -filepath $finalOutput -Append
        }

        else{
            Write-host "`nRegistration of $AWSaccount UNSUCCESSFUL!`n" -ForegroundColor Red 
            write-output "`n$dateTime    WARN    Registration of $AWSaccount UNSUCCESSFUL!`n"  | Out-File -FilePath $outfileName -Append
            write-output "`n$dateTime    WARN    Registration of $AWSaccount UNSUCCESSFUL!`n"  | Out-File -FilePath $finalOutput -Append
        }

        }

    else{
        Write-Host "`nNo valid AWS IAM ARN's retrieved!`n" -ForegroundColor Yellow 
        write-output "`n$dateTime    WARN    No valid AWS IAM ARN's retrieved!`n" | Out-File -FilePath $outfileName -Append 
    }
}
