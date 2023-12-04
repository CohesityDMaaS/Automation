# Unprotect an Object using PowerShell

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This powershell script unprotects objects in CCS.

Note: If the object has the same name for multiple workloads, each workload object with that name will be deleted.

Warning: This script has not been tested on every type of workload and with every permutation of object selections. Please test using a test object/group to ensure correct behavior. If incorrect behavior is noticed, please open an issue on GitHub.

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory

```powershell
# Download Commands
$scriptName = 'Unprotect_CCS_Objects'
$repoURL = 'https://raw.githubusercontent.com/CohesityDMaaS/Automation/main'
(Invoke-WebRequest -Uri "$repoUrl/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
(Invoke-WebRequest -Uri "$repoUrl/$scriptName/cohesity-api.ps1").content | Out-File cohesity-api.ps1; (Get-Content cohesity-api.ps1) | Set-Content cohesity-api.ps1
# End Download Commands
```

## Components

* Unprotect_CCS_Objects.ps1: the main powershell script
* cohesity-api.ps1: the Cohesity REST API helper module

Place both files in a folder together and run the main script like so:

```powershell
./Unprotect_CCS_Objects.ps1 -region us-east-2 `
                             -objectName myProtectedObject `
                             -deleteAllSnapshots $True `

```

Note: server names must exactly match what is shown in protection sources.

## Parameters

* -username: (optional) used for password storage only (default is 'DMaaS')
* -region: CCS region to use
* -objectName: (optional) comma separated list of object names to remove from jobs
* -objectList: (optional) text file containing object names to remove from jobs
* -deleteAllSnapshots: (optional) whether all Snapshots are deleted (default to $False)

## Authenticating to CCS

CCS uses an API key for authentication. To acquire an API key:

* log onto CCS
* click Settings -> access management -> API Keys
* click Add API Key
* enter a name for your key
* click Save

Immediately copy the API key (you only have one chance to copy the key. Once you leave the screen, you can not access it again). When running a CCS compatible script for the first time, you will be prompted for a password. Enter the API key as the password.
