# process commandline arguments
[CmdletBinding()]
param (
    [Parameter()][string]$username = 'DMaaS', # Your CCS username (username@emaildomain.com)
    [Parameter(Mandatory = $True)][string]$region,  # CCS region
    [Parameter(Mandatory = $True)][string]$sourceName,  # name of registered O365 source
    [Parameter()][array]$users,  # optional names of Onedrive(s) to unprotect
    [Parameter()][string]$userList = '',  # optional textfile of Onedrive(s) to unprotect
    [Parameter(Mandatory = $False)][bool]$deleteAllSnapshots = $False,  # whether all Snapshots are deleted (default to $False)
    [Parameter()][int]$pageSize = 50000
)

$outfileName = ".\log-Unprotect_CCS_M365OneDrives-$dateString.txt"

# gather list of onedrives to unprotect
$usersToAdd = @()
foreach($driveUser in $users){
    $usersToAdd += $driveUser
}
if ('' -ne $userList){
    if(Test-Path -Path $userList -PathType Leaf){
        $users = Get-Content $userList
        foreach($driveUser in $users){
            $usersToAdd += [string]$driveUser
        }
    }else{
        Write-Host "OneDrive list $userList not found!" -ForegroundColor Yellow
        exit
    }
}

$usersToAdd = @($usersToAdd | Where-Object {$_ -ne ''})

if($usersToAdd.Count -eq 0){
    Write-Host "No OneDrives specified" -ForegroundColor Yellow
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
    Write-Host "Source $sourceName is not configured for O365 OneDrives" -ForegroundColor Yellow
    exit
}

$nameIndex = @{}
$smtpIndex = @{}
$users = api get "protectionSources?pageSize=$pageSize&nodeId=$($usersNode.protectionSource.id)&id=$($usersNode.protectionSource.id)&hasValidOnedrive=true&allUnderHierarchy=false"
while(1){
    # implement pagination
    foreach($node in $users.nodes){
        $nameIndex[$node.protectionSource.name] = $node.protectionSource.id
        $smtpIndex[$node.protectionSource.office365ProtectionSource.primarySMTPAddress] = $node.protectionSource.id
    }
    $cursor = $users.nodes[-1].protectionSource.id
    $users = api get "protectionSources?pageSize=$pageSize&nodeId=$($usersNode.protectionSource.id)&id=$($usersNode.protectionSource.id)&hasValidOnedrive=true&allUnderHierarchy=false&afterCursorEntityId=$cursor"

    if(!($users[0].PSObject.Properties['nodes']) -or $users[0].nodes.Count -eq 1){
        break
    }
}  

#Unprotect the Mailboxes if they are already protected
#Write-Host "Determining if the M365 Source(s) is already Protected..." #Work in Progress 7/20/2022 8:27PM

# find users
foreach($driveUser in $usersToAdd){
    $userId = $null
    if($smtpIndex.ContainsKey($driveUser)){
        $userId = $smtpIndex[$driveUser]
    }elseif($nameIndex.ContainsKey($driveUser)){
        $userId = $nameIndex[$driveUser]
    }
          
	  if($userId){
        write-host "Unprotecting $driveUser.." 

        # configure unprotection parameters
        $unProtectionParams = @{
            "action" = "UnProtect";
            "objectActionKey" = "kO365OneDrive";
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
        $unprotectResponse | out-file -filepath .\$outfileName -Append
        Write-Host "Unprotected $driveUser"
		}
    Else {"Unable to Find $driveUser in order to unprotect." }
   }
