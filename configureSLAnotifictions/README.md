# Configure DMaaS SLA Notifications using Powershell

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This powershell script configures DMaaS SLA Notifications.

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory

```powershell
# Download Commands
$scriptName = 'configureSLAnotifications'
$repoURL = 'https://raw.githubusercontent.com/CohesityDMaaS/Automation/main/'
(Invoke-WebRequest -Uri "$repoUrl/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
# End Download Commands
```

## Components

* configureSLAnotifications.ps1: the main powershell script

Run the main script like so:

```powershell
./configureSLAnotifications.ps1 -apiKey ****** -regionId us-east-1 -ruleName "SLA_Alerts" -emailAddresses "test@duh.com, blah@test.com" -violations All -source server.domain.com
```

## Parameters

* -apiKey: apiKey generated in DMaaS UI
* -regionId: DMaaS SQL Source Region Id
* -ruleName: SLA Alert Notification Rule Name
* -source: reference Registered Source to validate DMaaS Cluster
* -emailAddresses: emails addresses that will be notified to SLA Violations
* -violations:  All by default

## Authenticating to DMaaS

DMaaS uses an API key for authentication. To acquire an API key:

* log onto DMaaS
* click Settings -> access management -> API Keys
* click Add API Key
* enter a name for your key
* click Save

Immediately copy the API key (you only have one chance to copy the key. Once you leave the screen, you can not access it again).
