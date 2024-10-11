# process commandline arguments
[CmdletBinding()]
param (
    [Parameter()][string]$username = 'DMaaS', # Your CCS username (username@emaildomain.com)
    [Parameter(Mandatory = $True)][string]$region,  # CCS region
    [Parameter(Mandatory = $True)][string]$sourceName,  # name of registered O365 source
    [Parameter()][array]$sites,  # optional names of SharePoint sites to unprotect
    [Parameter()][string]$siteList = '',  # optional textfile of SharePoint sites to unprotect
    [Parameter(Mandatory = $False)][bool]$deleteAllSnapshots = $false,  # whether all Snapshots are deleted (default to $False)
    [Parameter()][int]$pageSize = 50000
)

$outfileName = ".\log-Unprotect_CCS_M365Sites-$dateString.txt"

# gather list of SharePoint sites to unprotect
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
        $uniqueKey = "$($node.protectionSource.name)-$($node.protectionSource.id)"
        $nameIndex[$uniqueKey] = $node.protectionSource.id
    }
    $cursor = $users.nodes[-1].protectionSource.id
    $users = api get "protectionSources?pageSize=$pageSize&nodeId=$($sitesNode.protectionSource.id)&id=$($sitesNode.protectionSource.id)&hasValidSites=true&allUnderHierarchy=false&afterCursorEntityId=$cursor"
    if(!$users.PSObject.Properties['nodes'] -or $users.nodes.Count -eq 1){
        break
    }
}

# find sites
foreach($site in $sitesToAdd){
    $matchSites = $nameIndex.Keys | Where-Object { $_ -like "*$site*" }
    
    if ($matchSites.Count -gt 0) {
        foreach ($match in $matchSites) {
            $userId = $nameIndex[$match]

            # Attempt to get protection status for the site
            try {
                Write-Host "Checking protection status for $match..." -ForegroundColor Cyan
                #$protectionStatus = api get -v2 "data-protect/protected-objects/$userId"
                $protectionStatus = api get -v2 "data-protect/search/protected-objects?objectIds=$userId&objectActionKey=kO365Sharepoint"                
                
                if ($protectionStatus) {
                    if ($protectionStatus.numResults -gt 0) {
                        Write-Host "Unprotecting $match..." -ForegroundColor Green
                        # Configure unprotection parameters
                        $unProtectionParams = @{
                            "action" = "UnProtect";
                            "objectActionKey" = "kO365Sharepoint";
                            "unProtectParams" = @{
                                "objects" = @( 
                                    @{
                                        "id" = $userId;
                                        "deleteAllSnapshots" = $deleteAllSnapshots;
                                        "forceUnprotect" = $true;
                                    };
                                );
                            };
                        }

                        # Unprotect objects
                        $unprotectResponse = api post -v2 data-protect/protected-objects/actions $unProtectionParams 
                        $unprotectResponse | out-file -filepath .\$outfileName -Append
                        Write-Host "Unprotected $match" -ForegroundColor Green
                    } else {
                        Write-Host "$match is not currently protected, skipping unprotection." -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "Protection status for $match not found, skipping." -ForegroundColor Red
                }
            }
            catch {
                # Handle the case where protection status is not found (i.e., not protected)
                Write-Host "Error fetching protection status for $match, skipping." -ForegroundColor Red
            }
        }
    } else {
        Write-Host "Unable to find $site in order to unprotect." -ForegroundColor Yellow
    }
}
