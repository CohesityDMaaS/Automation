# process commandline arguments
[CmdletBinding()]
param (
    [Parameter()][string]$username = 'DMaaS', # Your CCS username (username@emaildomain.com)
    [Parameter(Mandatory = $True)][string]$region,  # CCS region
    [Parameter(Mandatory = $True)][string]$sourceName,  # name of registered O365 source
    [Parameter()][array]$mailboxes,  # optional names of mailboxes protect use @() for array of mailboxes
    [Parameter()][string]$mailboxList = '', # optional textfile of mailboxes to protect 'Mailbox_list.txt', 
    [Parameter(Mandatory = $False)][bool]$deleteAllSnapshots = $False,  # whether all Snapshots are deleted (default to $False)
    [Parameter()][int]$pageSize = 50000
)

# gather list of mailboxes to unprotect
$mailboxesToAdd = @()
foreach($mailbox in $mailboxes){
    $mailboxesToAdd += $mailbox
}
if ('' -ne $mailboxList){
    if(Test-Path -Path $mailboxList -PathType Leaf){
        $mailboxes = Get-Content $mailboxList
        foreach($mailbox in $mailboxes){
            $mailboxesToAdd += [string]$mailbox
        }
    }else{
        Write-Host "mailbox list $mailboxList not found!" -ForegroundColor Yellow
        exit
    }
}

$mailboxesToAdd = @($mailboxesToAdd | Where-Object {$_ -ne ''})

if($mailboxesToAdd.Count -eq 0){
    Write-Host "No mailboxes specified" -ForegroundColor Yellow
    exit
}


# source the cohesity-api helper code
. $(Join-Path -Path .\ -ChildPath cohesity-api.ps1)

# authenticate
apiauth -username $username -regionid $region

# find O365 source
$rootSource = api get protectionSources/rootNodes?environments=kO365 | Where-Object {$_.protectionSource.name -eq $sourceName}
if(!$rootSource){
    Write-Host "O365 Source $sourceName not found" -ForegroundColor Yellow
    exit
}
$source = api get "protectionSources?id=$($rootSource.protectionSource.id)&excludeOffice365Types=kMailbox,kUser,kGroup,kSite,kPublicFolder,kTeam,kO365Exchange,kO365OneDrive,kO365Sharepoint&allUnderHierarchy=false"
$usersNode = $source.nodes | Where-Object {$_.protectionSource.name -eq 'Users'}
if(!$usersNode){
    Write-Host "Source $sourceName is not configured for O365 Mailboxes" -ForegroundColor Yellow
    exit
}

$nameIndex = @{}
$smtpIndex = @{}
$users = api get "protectionSources?pageSize=$pageSize&nodeId=$($usersNode.protectionSource.id)&id=$($usersNode.protectionSource.id)&hasValidMailbox=true&allUnderHierarchy=false"
while(1){
    # implement pagination
    foreach($node in $users.nodes){
        $nameIndex[$node.protectionSource.name] = $node.protectionSource.id
        $smtpIndex[$node.protectionSource.office365ProtectionSource.primarySMTPAddress] = $node.protectionSource.id
    }
    $cursor = $users.nodes[-1].protectionSource.id
    $users = api get "protectionSources?pageSize=$pageSize&nodeId=$($usersNode.protectionSource.id)&id=$($usersNode.protectionSource.id)&hasValidMailbox=true&allUnderHierarchy=false&afterCursorEntityId=$cursor"
    if(!$users.PSObject.Properties['nodes'] -or $users.nodes.Count -eq 1){
        break
    }
}  

#Unprotect the Mailboxes if they are already protected
#Write-Host "Determining if the M365 Source(s) is already Protected..." #Work in Progress 7/20/2022 8:27PM
 
# find users
foreach($mailbox in $mailboxesToAdd){
    $userId = $null
    if($smtpIndex.ContainsKey($mailbox)){
        $userId = $smtpIndex[$mailbox]
    }elseif($nameIndex.ContainsKey($mailbox)){
        $userId = $nameIndex[$mailbox]
    }            



    if($userID){
        write-host "Unprotecting $mailbox.." 

        # configure unprotection parameters
        $unProtectionParams = @{
            "action" = "UnProtect";
            "objectActionKey" = "kO365Exchange";
            "unProtectParams" = @{
                "objects" = @( 
                    @{
                        "id" = $userID;
                        "deleteAllSnapshots" = $deleteAllSnapshots;
                        "forceUnprotect" = $true;
                    };
                );
            };
           }

        # unprotect objects
        $unprotectResponse = api post -v2 data-protect/protected-objects/actions $unProtectionParams 
        #$unprotectResponse | out-file -filepath .\$outfileName -Append
        Write-Host "Unprotected $mailbox"
    }
    Else {"Unable to Find $mailbox in order to unprotect prior to assigning new Protection configuration." }
   }
