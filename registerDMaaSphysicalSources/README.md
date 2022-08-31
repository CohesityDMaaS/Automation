# Register DMaaS Physical using PowerShell

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This powershell script registers DMaaS SQL Sources.

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory

```powershell
# Download Commands
$scriptName = 'registerDMaaSphysicalSources'
$repoURL = 'https://raw.githubusercontent.com/ezaborowski/Cohesity_Advanced_Services/main'
(Invoke-WebRequest -Uri "$repoUrl/PowerShell/DMaaS/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
# End Download Commands
```

## Components

* registerDMaaSphysicalSources.ps1: the main powershell script

Run the main script like so:

```powershell
./registerDMaasSQLsources.ps1 -apiKey API-KEY -regionId us-east-2 -saasConn "Saas_Connection-Name" -hostType kWindows -environment kPhysical -physType kHost -phylist ./physList.txt
```

## Parameters

* -apiKey: apiKey generated in DMaaS UI
* -regionId: DMaaS region to use
* -saasConn: name of SaaS Connection to associate with Physical Source
* -hostType: Physical Source OS type (kWindows, kLinux)
* -environment: environment type (kPhysical, kVMware, kAWS, kO365, kNetapp)
* -physType:  Source type (kHost, kVCenter, kIAMUser, kDomain, kCluster)
* -physFQDN: (optional) one or more Physical Source FQDNs (comma separated)
* -phylist: (optional) text file of Physical Source FQDNs (one per line)


## Authenticating to DMaaS

DMaaS uses an API key for authentication. To acquire an API key:

* log onto DMaaS
* click Settings -> access management -> API Keys
* click Add API Key
* enter a name for your key
* click Save

Immediately copy the API key (you only have one chance to copy the key. Once you leave the screen, you can not access it again).
