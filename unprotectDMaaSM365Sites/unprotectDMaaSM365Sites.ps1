# process commandline arguments
[CmdletBinding()]
param (
    [Parameter()][string]$username = 'DMaaS', # Your DMaaS username (username@emaildomain.com)
    [Parameter(Mandatory = $True)][string]$region,  # DMaaS region
    [Parameter(Mandatory = $True)][string]$sourceName,  # name of registered O365 source
    [Parameter()][array]$sites,  # optional names of sites to unprotect
    [Parameter()][string]$siteList = '',  # optional textfile of sites to unprotect
    [Parameter(Mandatory = $False)][bool]$deleteAllSnapshots = $False,  # whether all Snapshots are deleted (default to $False)
    [Parameter()][int]$pageSize = 50000
)

# gather list of sites to protect
$sitesToAdd = @()
foreach($site in $sites){
    $sitesToAdd += $site
}
if ('' -ne $siteList){
    if(Test-Path -Path $siteList -PathType Leaf){
        $sites = Get-Content $siteList
        foreach($site in $sites){
            $sitesToAdd += [string]$site
        }
    }else{
        Write-Host "Site list $siteList not found!" -ForegroundColor Yellow
        exit
    }
}

$sitesToAdd = @($sitesToAdd | Where-Object {$_ -ne ''})

if($sitesToAdd.Count -eq 0){
    Write-Host "No Sites specified" -ForegroundColor Yellow
    exit
}

# source the cohesity-api helper code
. $(Join-Path -Path .\ -ChildPath cohesity-api.ps1)

# authenticate
apiauth -username $username -regionid $region

$rootSource = api get protectionSources/rootNodes?environments=kO365 | Where-Object {$_.protectionSource.name -eq $sourceName}
if(!$rootSource){
    Write-Host "O365 Source $sourceName not found" -ForegroundColor Yellow
    exit
}

$source = api get "protectionSources?id=$($rootSource.protectionSource.id)&excludeOffice365Types=kMailbox,kUser,kGroup,kSite,kPublicFolder,kTeam,kO365Exchange,kO365OneDrive,kO365Sharepoint&allUnderHierarchy=false"
$sitesNode = $source.nodes | Where-Object {$_.protectionSource.name -eq 'Sites'}
if(!$sitesNode){
    Write-Host "Source $sourceName is not configured for M365 Sites" -ForegroundColor Yellow
    exit
}

$nameIndex = @{}
#$smtpIndex = @{}

$users = api get "protectionSources?pageSize=$pageSize&nodeId=$($sitesNode.protectionSource.id)&id=$($sitesNode.protectionSource.id)&hasValidSites=true&allUnderHierarchy=false"

while(1){
    # implement pagination
    foreach($node in $users.nodes){
        $nameIndex[$node.protectionSource.name] = $node.protectionSource.id
    }
    $cursor = $users.nodes[-1].protectionSource.id
    $users = api get "protectionSources?pageSize=$pageSize&nodeId=$($sitesNode.protectionSource.id)&id=$($sitesNode.protectionSource.id)&hasValidSites=true&allUnderHierarchy=false&afterCursorEntityId=$cursor"
    if(!$users.PSObject.Properties['nodes'] -or $users.nodes.Count -eq 1){
        break
    }
}

# find sites
foreach($site in $sitesToAdd){
    $userId = $null
    if($smtpIndex.ContainsKey("$site")){
        $userId = $smtpIndex["$site"]
    }
    elseif($nameIndex.ContainsKey("$site")){
        $userId = $nameIndex["$site"]
    }   
if($userId){
        write-host "Unprotecting $site.." 

        # configure unprotection parameters
        $unProtectionParams = @{
            "action" = "UnProtect";
            "objectActionKey" = "kO365Sharepoint";
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
        Write-Host "Unprotected $site"
		}
    Else {"Unable to Find $site in order to unprotect." }
   }
