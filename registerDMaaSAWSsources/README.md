# Register DMaaS AWS Source using PowerShell

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This powershell script registers DMaaS AWS Sources.

## Prerequisites

The user running the script must first set AWS Admin Credentials within Powershell by using the following commands:
```powershell
Set-AWSCredentials -AccessKey xxxxxx -SecretKey xxxxxxx -StoreAs MyMainUserProfile
Validate: Get-AWSCredential -ListProfileDetail
Initialize-AWSDefaultConfiguration -ProfileName MyMainUserProfile -Region us-west-2
```

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory

```powershell
# Download Commands
$scriptName = 'registerDMaaSAWSsources'
$repoURL = 'https://raw.githubusercontent.com/CohesityDMaaS/Automation/main'
(Invoke-WebRequest -Uri "$repoUrl/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
(Invoke-WebRequest -Uri "$repoUrl/$scriptName/README.md").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "README.md"
# End Download Commands
```

## Components

* registerDMaaSAWSsources.ps1: the main powershell script

Run the main script like so:

```powershell
./registerDMaaSAWSsources.ps1 -apiKey XXXXXXX -regionId us-east-1 -awsRegion us-east-2 -AWSid XXXXXXX -roleArn "AWS_ARN"

./registerDMaaSAWSsources.ps1 -apiKey XXXXXXX -regionId us-east-1 -awsRegion us-east-2 -AWSid XXXXXXX -awsLogin
```

## Parameters

* -apiKey: apiKey generated in DMaaS UI
* -regionId: DMaaS region where AWS Account ID is to be Registered
* -awsRegion: AWS region where AWS Account ID is Registered
* -AWSid: (optional) one or more AWS Account ID's (comma separated)
* -AWSlist: (optional) text file of AWS Account ID's (one per line)
    * it is mandatory that you use one of either AWSid or AWSlist (or both can be used, if needed)
* -roleARN: (optional) AWS IAM ARN associated with CFT Deployment IAM Role (comma separated)
* -ARNlist: (optional) text file of AWS IAM ARN's associated with CFT Deployment IAM Roles (one per line)
    * it is mandatory that you use one of either roleARN or ARNlist (or both can be used, if needed), UNLESS using -awsLogin switch and then neither of these variables should be used
* -awsLogin: (optional) switch to enable prompting of AWS Account AccessKey, SecretKey, and AWS Profile Name instead of script assuming AWS IAM Role


## Authenticating to DMaaS

DMaaS uses an API key for authentication. To acquire an API key:

* log onto DMaaS
* click Settings -> access management -> API Keys
* click Add API Key
* enter a name for your key
* click Save

Immediately copy the API key (you only have one chance to copy the key. Once you leave the screen, you can not access it again).
