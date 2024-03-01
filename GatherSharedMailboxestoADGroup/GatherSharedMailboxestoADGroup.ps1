#Install Modules
Install-Module -Name AzureAD
Install-Module -Name ExchangeOnlineManagement

#Import Modules
Import-Module AzureAD
Import-Module ExchangeOnlineManagement

# Connect to AzureAD and Exchange Online

Connect-AzureAD 
Connect-ExchangeOnline 

#Define GroupName
$groupName = "<<AzureADGroupName>>"
$groupObjectId = "<<AzureGroupObjectID>>"

#Get All Shared Mailboxes
$sharedMailboxes = Get-Mailbox -RecipientTypeDetails SharedMailbox

# Loop through the shared mailboxes and add them to the Azure AD group.
foreach ($mailbox in $sharedMailboxes) {
    $user = Get-AzureADUser -ObjectId $mailbox.ExternalDirectoryObjectId -ErrorAction SilentlyContinue
    if ($user) {
        Add-AzureADGroupMember -ObjectId $groupObjectId -RefObjectId $user.ObjectId 
    }
}
