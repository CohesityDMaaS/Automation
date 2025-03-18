# Run object detail reports for FortKnox using PowerShell

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This powershell script queries protection group object level detail on local backup and post vaulting status.

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory

```powershell
# Download Commands
$scriptName = 'FortKnox_Reporting'
$repoURL = 'https://raw.githubusercontent.com/CohesityDMaaS/Automation/main'
(Invoke-WebRequest -Uri "$repoUrl/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
(Invoke-WebRequest -Uri "$repoUrl/$scriptName/cohesity-api.ps1").content | Out-File cohesity-api.ps1; (Get-Content cohesity-api.ps1) | Set-Content cohesity-api.ps1
# End Download Commands
```

## Components

* FortKnox_Reporting.ps1: the main powershell script
* cohesity-api.ps1: the Cohesity REST API helper module

Place both files in a folder together and run the main script like so:

```powershell
./FortKnox_Reporting.ps1 --username heliosUserName@company.org -clusterName <clustername>

All Helios connected clusters Example
./FortKnox_Reporting.ps1 --username heliosUserName@company.org -numRuns 1250
```

## Parameters

* -username: (optional) used for password storage only 
* -apiKey: api key associated to username in Helios
* -clustername: (optional) cluster name to run report against, default is all Helios connected clusters if no name is provided
* -numRuns: (optional) default is 1000

## Authenticating to FortKnox

Helios uses an API key for authentication. To acquire an API key:

* log onto Cohesity Cloud Services>FortKnox
* click Settings -> access management -> API Keys
* click Add API Key
* enter a name for your key
* click Save

Immediately copy the API key (you only have one chance to copy the key. Once you leave the screen, you can not access it again). When running a CCS compatible script for the first time, you will be prompted for a password. Enter the API key as the password.