# process commandline arguments
[CmdletBinding()]
param (
    [Parameter()][string]$username = 'DMaaS',
    [Parameter(Mandatory = $True)][string]$region,  # DMaaS region
    [Parameter(Mandatory = $True)][string]$policyName,  # protection policy name
    [Parameter(Mandatory = $True)][string]$sourceName,  # name of registered O365 source
    [Parameter()][array]$sites,  # optional names of Sites protect
    [Parameter()][string]$siteList,  # optional textfile of Sites to protect
    [Parameter()][string]$startTime = '20:00',  # e.g. 23:30 for 11:30 PM
    [Parameter()][string]$timeZone = 'America/New_York', # e.g. 'America/New_York'
    [Parameter()][int]$incrementalSlaMinutes = 60,  # incremental SLA minutes
    [Parameter()][int]$fullSlaMinutes = 120,  # full SLA minutes
    [Parameter()][int]$pageSize = 1000,
    [Parameter()][bool]$wildcard # if customer wants to search like terms and allows use of "*"
)

# gather list of sites to protect
if($sites){
    $sitesToAdd = @()
    foreach($site in $sites){
        $sitesToAdd += $site
    }
}
    elseif ('' -ne $siteList){
        $sitesToAdd = @()
        if(Test-Path -Path $siteList -PathType Leaf){
            $sites = Get-Content $siteList
            foreach($site in $sites){
                $sitesToAdd += [string]$site
            }
        }else{
            if($sites.count -eq 0){
            Write-Host "Site list $siteList not found!" -ForegroundColor Yellow
            exit
        }
        }
    }

    $sitesToAdd = @($sitesToAdd | Where-Object {$_ -ne ''})

    if($sitesToAdd.Count -eq 0){
    Write-Host "No Sites specified" -ForegroundColor Yellow
    exit
    }


# parse startTime
$hour, $minute = $startTime.split(':')
$tempInt = ''
if(! (($hour -and $minute) -or ([int]::TryParse($hour,[ref]$tempInt) -and [int]::TryParse($minute,[ref]$tempInt)))){
    Write-Host "Please provide a valid start time" -ForegroundColor Yellow
    exit
}

# source the cohesity-api helper code
. $(Join-Path -Path .\ -ChildPath cohesity-api.ps1)

# authenticate
apiauth -username $username -regionid $region

#Validate the proteciton Policy exists
$policy = (api get -mcmv2 data-protect/policies?types=DMaaSPolicy).policies | Where-Object name -eq $policyName
if(!$policy){
    write-host "Policy $policyName not found" -ForegroundColor Yellow
    exit
}

#Validate the site(s) to protect exist in the Tenant if a Wildcard is not used for protection
if(($sites -ne "All") -and ($wildcard -ne $True)){
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
}


if($wildcard -ne $True){ 
        $protectedSources = (api get -v2 data-protect/search/objects).objects | where-object objectType -eq "kSite"
        $unprotectedSources = (api get -v2 data-protect/search/objects?sourceUuids=$Source.protectionSource.name"&"searchString=*"&"isProtected=false"&"includeTenants=true).objects | where-object objectType -eq "kSite"
        if(!$unprotectedSources){
            write-host "No Sites found to be protected" -ForegroundColor Yellow
            exit
        }
        else{
            $userIds = @()
            $siteList = @()
            foreach($site in $sitesToAdd){
                $matchSites = $unprotectedSources | where-object name -like "$site"
            if(!$matchSites){
            write-host("No unprotected Sites matching $site")
            continue
            }
      if($matchSites){
            $siteId = ($matchSites.objectprotectioninfos | Where-object regionID -eq "$region" | Select-Object objectID).objectid
            $siteList += $matchSites.name
            $userIds += $siteId 
            write-host("Site ID matching " + $site + ": " + $userIds)
        }
    }
  }
 }


elseif($wildcard -eq $True){
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
    
    
    $userIds = @()
    $protectedSources = (api get -v2 data-protect/search/protected-objects).objects | where-object objectType -eq "kSite"
    $unprotectedSources = (api get -v2 data-protect/search/objects?sourceUuids=$Source.protectionSource.name"&"searchString=*"&"isProtected=false"&"includeTenants=true).objects | where-object objectType -eq "kSite"

    if(!$unprotectedSources){
        write-host "No Sites found to Protect with WildCard Search" -ForegroundColor Yellow
        exit
    }
    else{
        $userIds = @()
        $siteList = @()
        foreach($site in $sitesToAdd){
            $matchSites = $unprotectedSources | where-object name -like "*$site*"
            if(!$matchSites){
            write-host("No unprotected Sites matching $site")
            continue
        }
        if($matchSites){
            $siteIds = ($matchSites.objectprotectioninfos | Where-object regionID -eq "$region" | Select-Object objectID).objectid
            $siteList += $matchSites.name
            $userIds += $siteIds 
            write-host("Site ID matching " + $site + ": " + $siteIds)
            
        }

    

   }
  }
 }


# configure protection parameters
$protectionParams = @{
    "policyId"         = $policy.id;
    "startTime"        = @{
        "hour"     = [int64]$hour;
        "minute"   = [int64]$minute;
        "timeZone" = $timeZone
    };
    "priority"         = "kMedium";
    "sla"              = @(
        @{
            "backupRunType" = "kFull";
            "slaMinutes"    = $fullSlaMinutes
        };
        @{
            "backupRunType" = "kIncremental";
            "slaMinutes"    = $incrementalSlaMinutes
        }
    );
    "qosPolicy"        = "kBackupSSD";
    "abortInBlackouts" = $false;
    "objects"          = @()
}

$sitesAdded = 0

# Apply site information to protection parameters and protect
if(($sites -ne "All") -and ($wildcard -ne $True)){
    foreach($site in $siteList){
        $userId = $null
        if($nameIndex.ContainsKey("$site")){
            $userId = $nameIndex["$site"]
        }   
        if($userId){
            $protectionParams.objects = @(@{
                "environment"     = "kO365Sharepoint";
                "office365Params" = @{
                    "objectProtectionType"              = "kSharePoint";
                    "sharepointSiteObjectProtectionParams" = @{
                        "objects"        = @(
                            @{
                                "id" = $userId
                                "shouldAutoProtectObject" = $false
                            }
                        );
                        "indexingPolicy" = @{
                            "enableIndexing" = $true;
                            "includePaths"   = @(
                                "/"
                            );
                            "excludePaths"   = @()
                        }
                    }
                }
            })
            Write-Host "Protecting Site for $site"
            $response = api post -v2 data-protect/protected-objects $protectionParams
        }else{
            Write-Host "Site for $site not found" -ForegroundColor Yellow
        }
    }
}
else{
    foreach($userId in $userIds){
        if($userId){
            $protectionParams.objects = @(@{
                "environment"     = "kO365Sharepoint";
                "office365Params" = @{
                    "objectProtectionType"              = "kSharePoint";
                    "sharepointSiteObjectProtectionParams" = @{
                        "objects"        = @(
                            @{
                                "id" = $userId
                                "shouldAutoProtectObject" = $false
                            }
                        );
                        "indexingPolicy" = @{
                            "enableIndexing" = $true;
                            "includePaths"   = @(
                                "/"
                            );
                            "excludePaths"   = @()
                        }
                    }
                }
            })
            Write-Host "Protecting Site for $userId"
            $response = api post -v2 data-protect/protected-objects $protectionParams
        }
        else{
            Write-Host "ID not found" -ForegroundColor Yellow
        }
    }
}

