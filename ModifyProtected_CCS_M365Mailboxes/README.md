# Modifying CCS M365 Mailboxes using PowerShell
Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This powershell script removes protection for CCS M365 Mailboxes and them reprotects using the parameters specified. This script was created for the purpose of automating changes to a large nubmer of Manually Protected Mailboxes. 

In the body of the script, you can specify exclude folders by adjusting the parameters on line 183
 
If you want to include all Items, adjust the line to an empty array 
- ie: 
```powershell
"excludeFolders" = @()
```
If you want to "Exclude" Calendar, Archive and Recycle bin items, then add them to the array list.
```powershell
"excludeFolders" = @("Calendar","In-Place archive","Recoverable Items")
```
If you want to "include" Calendar items, then remove it from the list.
```powershell
"excludeFolders" = @("In-Place archive","Recoverable Items")
```
# Download the script
Run these commands from PowerShell to download the script(s) into your current directory

```powershell
# Download Commands
$scriptName = 'ModifyProtected_CCS_M365Mailboxes' 
$repoURL = 'https://raw.githubusercontent.com/CohesityDMaaS/Automation/main'
(Invoke-WebRequest -Uri "$repoUrl/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
(Invoke-WebRequest -Uri "$repoUrl/$scriptName/cohesity-api.ps1").content | Out-File cohesity-api.ps1; (Get-Content cohesity-api.ps1) | Set-Content cohesity-api.ps1
# End Download Commands
```

# Components
- ModifyProtected_CCS_M365Mailboxes.ps1: the main powershell script
 -cohesity-api.ps1: the Cohesity REST API helper module
Place both files in a folder together and run the main script like so:
```powershell
./ModifyProtected_CCS_M365Mailboxes.ps1 -region us-east-2 -sourceName mydomain.onmicrosoft.com -mailboxes user1.mydomain.onmicrosoft.com, user2.mydomain.onmicrosoft.com  -mailboxList ./mailboxlist.txt
```
# Parameters
- username: (optional) used for password storage only (default is 'DMaaS')
- region: CCS region to use
- sourceName: name of registered M365 protection source
- policyName: name of protection policy to use
- mailboxes: (optional) one or more mailbox names or SMTP addresses (comma separated)
- mailboxList: (optional) text file of mailbox names or SMTP addresses (one per line)
- startTime: (optional) e.g. '18:30' (defaults to 8PM)
- timeZone: (optional) e.g. 'America/New_York' (default is 'America/New_York')
- incrementalSlaMinutes: (optional) default 60
- fullSlaMinutes: (optional) default is 120
- pageSize: (optional) limit number of objects returned pr page (default is 50000)

# Authenticating to CCS

CCS uses an API key for authentication. To acquire an API key:

- log onto CCS
- click Settings -> access management -> API Keys
- click Add API Key
- enter a name for your key
- click Save

Immediately copy the API key (you only have one chance to copy the key. Once you leave the screen, you can not access it again). When running a CCS compatible script for the first time, you will be prompted for a password. Enter the API key as the password.