# process commandline arguments
[CmdletBinding()]
param (
    [Parameter()][string]$username = 'DMaaS', # Your CCS username (username@emaildomain.com)
    [Parameter(Mandatory = $True)][string]$region,  # CCS region
    [Parameter(Mandatory = $True)][string]$sourceName,  # name of registered O365 source
    [Parameter()][array]$teams,  # optional names of MS Teams to unprotect
    [Parameter()][string]$teamsList = '',  # optional textfile of MS Teams to unprotect
    [Parameter(Mandatory = $False)][bool]$deleteAllSnapshots = $False,  # whether all Snapshots are deleted (default to $False)
    [Parameter()][int]$pageSize = 50000
)

# gather list of MS Teams to unprotect
$teamsToAdd = @()
foreach($team in $teams){
    $teamsToAdd += $team
}
if ('' -ne $teamsList){
    if(Test-Path -Path $teamsList -PathType Leaf){
        $teams = Get-Content $teamsList
        foreach($team in $teams){
            $teamsToAdd += [string]$team
        }
    }else{
        Write-Host "Teams list $teamsList not found!" -ForegroundColor Yellow
        exit
    }
}

$outfileName = "$PSScriptRoot\log-Unprotect_CCS_M365Teams-$dateString.txt"

$teamsToAdd = @($teamsToAdd | Where-Object {$_ -ne ''})

if($teamsToAdd.Count -eq 0){
    Write-Host "No Teams specified" -ForegroundColor Yellow
    exit
}

# source the cohesity-api helper code
. $(Join-Path -Path .\ -ChildPath cohesity-api.ps1)

# authenticate
apiauth -username $username -regionid $region

# finding O365 Source
$rootSource = api get protectionSources/rootNodes?environments=kO365 | Where-Object {$_.protectionSource.name -eq $sourceName}
if(!$rootSource){
    Write-Host "O365 Source $sourceName not found" -ForegroundColor Yellow
    exit
}

$source = api get "protectionSources?id=$($rootSource.protectionSource.id)&excludeOffice365Types=kMailbox,kUser,kGroup,kSite,kPublicFolder,kTeam,kO365Exchange,kO365OneDrive,kO365Sharepoint&allUnderHierarchy=false"
$teamsNode = $source.nodes | Where-Object {$_.protectionSource.name -eq 'Teams'}
if(!$teamsNode){
    Write-Host "Source $sourceName is not configured for M365 Teams" -ForegroundColor Yellow
    exit
}

$nameIndex = @{}
$smtpIndex = @{}

$users = api get "protectionSources?pageSize=$pageSize&nodeId=$($teamsNode.protectionSource.id)&id=$($teamsNode.protectionSource.id)&hasValidTeams=true&allUnderHierarchy=false"

while(1){
    # implement pagination
    foreach($node in $users.nodes){
        $nameIndex[$node.protectionSource.name] = $node.protectionSource.id
        $smtpIndex[$node.protectionSource.office365ProtectionSource.primarySMTPAddress] = $node.protectionSource.id
    }
    $cursor = $users.nodes[-1].protectionSource.id
    $users = api get "protectionSources?pageSize=$pageSize&nodeId=$($teamsNode.protectionSource.id)&id=$($teamsNode.protectionSource.id)&hasValidTeams=true&allUnderHierarchy=false&afterCursorEntityId=$cursor"
    if(!$users.PSObject.Properties['nodes'] -or $users.nodes.Count -eq 1){
        break
    }
}

# find teams
foreach($team in $teamsToAdd){
    $userId = $null
    if($smtpIndex.ContainsKey($team)){
        $userId = $smtpIndex[$team]
    }elseif($nameIndex.ContainsKey($team)){
        $userId = $nameIndex[$team]
    }   
    if($userId){
        write-host "Unprotecting $team.." 

        # configure unprotection parameters
        $unProtectionParams = @{
            "action" = "UnProtect";
            "objectActionKey" = "kO365Teams";
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
        Write-Host "Unprotected $team"
		}
    Else {"Unable to Find $team in order to unprotect." }
   }
