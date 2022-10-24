# Register DMaaS AWS Source using PowerShell

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This powershell script registers DMaaS AWS Sources.

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory

```powershell
# Download Commands
$scriptName = 'registerDMaaSAWSsources'
$repoURL = 'https://raw.githubusercontent.com/ezaborowski/Cohesity_Advanced_Services/main/PowerShell/DMaaS'
(Invoke-WebRequest -Uri "$repoUrl/PowerShell/DMaaS/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
# End Download Commands
```

## Components

* registerDMaaSAWSsources.ps1: the main powershell script

Run the main script like so:

```powershell
./registerDMaaSAWSsources.ps1 -apiKey XXXXXXX -regionId us-east-1 -AWSid XXXXXXX -roleArn "AWS_ARN"
```

## Parameters

* -apiKey: apiKey generated in DMaaS UI
* -regionId: DMaaS region to use
* -AWSid: (optional) one or more AWS Account ID's (comma separated)
* -AWSlist: (optional) text file of AWS Account ID's (one per line) 
    * it is mandatory that you use one of either AWSid or AWSlist
* -roleARN:  (optional) AWS ARN associated with CFT Deployment IAM Role
* -ARNlist =  (optional) text file of AWS ARN's associated with CFT Deployment IAM Roles  
    * it is mandatory that you use one of either roleARN or ARNlist


## Authenticating to DMaaS

DMaaS uses an API key for authentication. To acquire an API key:

* log onto DMaaS
* click Settings -> access management -> API Keys
* click Add API Key
* enter a name for your key
* click Save

Immediately copy the API key (you only have one chance to copy the key. Once you leave the screen, you can not access it again).
