# Refresh CCS Sources

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This powershell script Refreshes CCS Sources.

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory
```powershell
# Download Commands
$scriptName = 'CCS_Source_Refresh'
$repoURL = 'https://raw.githubusercontent.com/CohesityDMaaS/Automation/main'
(Invoke-WebRequest -Uri "$repoUrl/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
(Invoke-WebRequest -Uri "$repoUrl/$scriptName/cohesity-api.ps1").content | Out-File cohesity-api.ps1; (Get-Content cohesity-api.ps1) | Set-Content cohesity-api.ps1
# End Download Commands
```

## Components
* Ensure that the below two components are saved in the same directory:

* CCS_Source_Refresh.ps1: the main powershell script
* cohesity-api.ps1: the Cohesity REST API helper module

Place both files in a folder together and run the main script like so:

```powershell
./CCS_Source_Refresh.ps1 -region us-east-2 -sourceID 772,3306
```

## Parameters

* region: CCS region to use
* username: (optional) used for password storage only (default is 'DMaaS')
* sourceID: ID of registered M365 protection source

The ID of a Cohesity CCS Source can be found in the navigation bar of the internet browser after having clicked on the Source Name:
https://helios.cohesity.com/protections/sources/details/187694/objects?regionId=us-west-1&environment=kVMware

In the above address, the Source ID is: 187694

## Authenticating to CCS

CCS uses an API key for authentication. To acquire an API key:

* log onto CCS
* click Settings -> access management -> API Keys
* click Add API Key
* enter a name for your key
* click Save

Immediately copy the API key (you only have one chance to copy the key. Once you leave the screen, you can not access it again). When running a CCS compatible script for the first time, you will be prompted for a password. Enter the API key as the password.
