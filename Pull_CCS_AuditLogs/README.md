# Pull CCS Audit Logs using PowerShell

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This powershell script pulls CCS Audit Logs and saves them in JSON format. This script also has a functionality which allows the customer to push their CCS Audit Logs to a webhook for third party analysis (ie: SumoLogic, ServiceNow, etc.).

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory

```powershell
# Download Commands
$scriptName = 'Pull_CCS_AuditLogs'
$repoURL = 'https://raw.githubusercontent.com/CohesityDMaaS/Automation/main'
(Invoke-WebRequest -Uri "$repoUrl/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
(Invoke-WebRequest -Uri "$repoUrl/$scriptName/README.md").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "README.md"
# End Download Commands
```

## Components

* Pull_CCS_AuditLogs.ps1: the main powershell script

Run the main script like so:

```powershell
./Pull_CCS_AuditLogs.ps1 -apiKey XXXXXXX -regionAll

./Pull_CCS_AuditLogs.ps1 -apiKey XXXXXXX -regionId us-east-2, us-west-1 - days 3
```

## Parameters

* -apiKey: apiKey generated in CCS UI
* -regionId: (optional) CCS region ID(s) (comma separated)
* -regionAll: (optional) switch to indicate that ALL CCS Regions will be pulled for Audit Report (recommended)
    * it is mandatory that you use one of either regionId or regionAll
* -days: (optional) how many days of logs to pull (default = 1)
* -uri: (optional) website accepting webhook data (ex: "https://webhook.site/a2633791-5ad1-473e-aad4-4dbda106676d")


## Authenticating to CCS

CCS uses an API key for authentication. To acquire an API key:

* log onto CCS
* click Settings -> access management -> API Keys
* click Add API Key
* enter a name for your key
* click Save

Immediately copy the API key (you only have one chance to copy the key. Once you leave the screen, you can not access it again).
