# Register DMaaS Generic NAS Sources using PowerShell
Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This powershell script registers Generic NAS sources. This script was created for the purpose of automating registration of a large nubmer of Generic NAS Sources into DMaaS to minimize time and effort. 

# Download the script
Run these commands from PowerShell to download the script(s) into your current directory

~~~
# Download Commands
$scriptName = 'RegisterDMaaSGenericNasSources' 
$repoURL = 'https://raw.githubusercontent.com/CohesityDMaaS/Automation/main'
(Invoke-WebRequest -Uri "$repoUrl/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
(Invoke-WebRequest -Uri "$repoUrl/$scriptName/cohesity-api.ps1").content | Out-File cohesity-api.ps1; (Get-Content cohesity-api.ps1) | Set-Content cohesity-api.ps1
# End Download Commands
~~~

## Components
* RegisterDMaaSGenericNasSources.ps1: the main powershell script
* cohesity-api.ps1: the Cohesity REST API helper module

Place both files in a folder together and run the main script like so:

~~~
./RegisterDMaaSGenericNasSources.ps1 -regionId us-east-2 -apiKey apikeyvalue -saasConn saasConnectorName -gNasUserName SMBUserName
~~~
# Parameters
- username: (optional) used for password storage only (default is 'DMaaS')
- regionId: DMaaS region to use
- gNasFQDNShare: genericNAS Source FQDN \\IPAddress\c$ or \\FQDN\ShareName
- gNasDescription: (optional) ngNas Description (Tech Team Share, HR Share, Documents)
- gNasList: (optional) 'C:\FolderPath\gNaslist.txt', file of Generic NAS Sources to protect
- gNasUserName: source Username with appropriate access (.\Admin, .\UserName_User)

# Authenticating to DMaaS

DMaaS uses an API key for authentication. To acquire an API key:

- log onto DMaaS
- click Settings -> access management -> API Keys
- click Add API Key
- enter a name for your key
- click Save

Immediately copy the API key (you only have one chance to copy the key. Once you leave the screen, you can not access it again). When running a DMaaS compatible script for the first time, you will be prompted for a password. Enter the API key as the password.
 