# Protect DMaaS Physical Sources using PowerShell

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This powershell script protects DMaaS Physical Sources.

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory

```powershell
# Download Commands
$scriptName = 'protectDMaaSphysicalSources'
$repoURL = 'https://raw.githubusercontent.com/CohesityDMaaS/Automation/main'
(Invoke-WebRequest -Uri "$repoUrl/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
(Invoke-WebRequest -Uri "$repoUrl/$scriptName/cohesity-api.ps1").content | Out-File cohesity-api.ps1; (Get-Content cohesity-api.ps1) | Set-Content cohesity-api.ps1
# End Download Commands
```

## Components

* protectDMaaSphysicalSources.ps1: the main powershell script

Run the main script like so:

```powershell
./protectDMaaSphysicalSources.ps1 -apiKey API-KEY -regionId us-east-2 -policy "Policy-Name" -startTime "00:00" -timeZone Americal/Chicago -physFQDN "source FQDN"
```

## Parameters

* -apiKey: apiKey generated in DMaaS UI
* -regionId: DMaaS region to use
* -policy: The policy name to be used for protection
* -startTime: Start time for incremental schedule format 00:00
* -timeZone: Time zone to be used for the start time
* -physFQDN: Source FQDN

## Authenticating to DMaaS

DMaaS uses an API key for authentication. To acquire an API key:

* log onto DMaaS
* click Settings -> access management -> API Keys
* click Add API Key
* enter a name for your key
* click Save

Immediately copy the API key (you only have one chance to copy the key. Once you leave the screen, you can not access it again).
