#PowerShell Capturing total M365 object counts
$tenantname = 'tenantname'
$tenantdomainname = 'tenantdomain'
$TenanaUrl = "https://$tenantname-admin.sharepoint.com/"
$UserPrincipalName = 'user@domain.com'
#$Creds = Get-Credential  

#Authenticate to Microsoft 365 PowerShell
Write-Host "Please Authenticate to Access Microsoft M365 Powershell"
Connect-MsolService
#Authenticate to Access Exchange Online
Write-Host "Please Authenticate to Access Exchange Online"
Connect-ExchangeOnline -UserPrincipalName $UserPrincipalName 
#Authenticate to Access SharePoint Online
Write-Host "Please Authenticate to SharePoint Online"
Connect-SPOService -Url https://$tenantname-admin.sharepoint.com/ 
#Authenticate to Azure for MS Groups Administration
Write-Host "Please Authenticate to Access MS Groups Information"
Connect-PnPOnline -Url https://$tenantname-admin.sharepoint.com/ -Interactive -ForceAuthentication
#Authenticate to MS Teams Administration
Write-Host "Please Authenticate to MS Teams"
Connect-MicrosoftTeams
#Authenticate to Azure Tenanat as Global Admin
Write-Host "Please Authenticate to Azure"
Connect-AzureAD

$mailboxcount = Get-ExoMailbox -ResultSize unlimited | Where-Object {$_.DisplayName -ne "Discovery Search Mailbox"} | Measure-Object

#$OneDrivecount = Get-PnPTenantSite -IncludeOneDriveSites -Filter "Url -like '-my.sharepoint.com/personal/'" -Detailed | Select | Measure-Object

$OneDrivecount = Get-MsolUser -All | Where-Object {($_.IsLicensed -eq $true) -and ($_.LastSignInDate -eq $null)} | Measure-Object
$Sharepointcount = Get-SPOSite -Limit All | Where-Object { $_.Template -ne "GROUP#0" -and $_.Template -ne "TEAMCHANNEL#0" } | Measure-Object
$MSGroupscount = Get-unifiedgroup -IncludeAllProperties| Measure-Object
$MSTeamscount = Get-Team | Measure-Object
$MSGroupscount = ($MSGroupscount.Count - $MSTeamscount.count)
$AzureADSecurityGroupcount = Get-AzureADGroup | Measure-Object
$M365Objectcount = @($mailboxcount.count + $OneDrivecount.count + $Sharepointcount.count + $MSGroupscount + $MSTeamscount.count)

#$M365ObjectcountIncludingAzureADGroups = @($mailboxcount.count + $OneDrivecount.count + $Sharepointcount.count + $MSGroupscount.count + $MSTeamscount.count + $AzureADSecurityGroupcount.count)
#$M365Objectcount
#$M365ObjectcountIncludingAzureADGroups
#Write-host "There are"$MSGroupsCount "MSGroups,"$mailboxcount.count"Exchange Mailboxes,"$Sharepointcount.count"SharePoint Sites,"$MSTeamscount.count"MS Teams and"$OneDrivecount.count"OneDrives, and"$AzureADSecurityGroupcount.count"AzureADGroups Totaling"$M365ObjectcountIncludingAzureADGroups" Objects for M365 Tenant $Tenantdomainname "

Write-host "------------------------------------------------------------------------------------------------------------------------------------------------------------------"
Write-host "There are"$mailboxcount.count"Exchange Mailboxes,"$OneDrivecount.count"OneDrives," $Sharepointcount.count"SharePoint Sites,"$MSTeamscount.count"MS Teams, and"$MSGroupsCount "MSGroups Totaling" $M365Objectcount" Objects for M365 Tenant $Tenantdomainname "
Write-host "------------------------------------------------------------------------------------------------------------------------------------------------------------------"