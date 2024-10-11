# Process command-line arguments
[CmdletBinding()]
param (
    [Parameter()][string]$username = 'DMaaS',
    [Parameter(Mandatory = $True)][string]$region,  # DMaaS region
    [Parameter(Mandatory = $True)][string]$policyName,  # Protection policy name
    [Parameter(Mandatory = $True)][string]$sourceName,  # Name of registered O365 source
    [Parameter()][array]$sites,  # Optional names of mailboxes to protect
    [Parameter()][string]$siteList,  # Optional text file of mailboxes to protect
    [Parameter()][string]$startTime = '20:00',  # e.g. 23:30 for 11:30 PM
    [Parameter()][string]$timeZone = 'America/New_York',  # e.g. 'America/New_York'
    [Parameter()][int]$incrementalSlaMinutes = 60,  # Incremental SLA minutes
    [Parameter()][int]$fullSlaMinutes = 120,  # Full SLA minutes
    [Parameter()][int]$pageSize = 1000,
    [Parameter()][bool]$wildcard  # If customer wants to search like terms and allows use of "*"
)

# Gather list of sites to protect
$sitesToAdd = @()

if ($sites -ne "All") {
    $sitesToAdd += $sites

    if ($siteList) {
        if (Test-Path -Path $siteList -PathType Leaf) {
            $sitesToAdd += Get-Content $siteList
        } else {
            Write-Host "Site list $siteList not found!" -ForegroundColor Yellow
            exit
        }
    }

    # Remove empty entries
    $sitesToAdd = $sitesToAdd | Where-Object { $_ -ne '' }

    if ($sitesToAdd.Count -eq 0) {
        Write-Host "No Sites specified" -ForegroundColor Yellow
        exit
    }
}

# Parse startTime
if (-not ($startTime -match '^\d{1,2}:\d{2}$')) {
    Write-Host "Please provide a valid start time" -ForegroundColor Yellow
    exit
}

$hour, $minute = $startTime.Split(':')

# Source the cohesity-api helper code
. $(Join-Path -Path .\ -ChildPath cohesity-api.ps1)

# Authenticate
apiauth -username $username -regionid $region

# Retrieve policy
$policy = (api get -mcmv2 data-protect/policies?types=DMaaSPolicy).policies | Where-Object name -eq $policyName
if (!$policy) {
    Write-Host "Policy $policyName not found" -ForegroundColor Yellow
    exit
}

# Fetch sites and process based on parameters
$nameIndex = @{}
$smtpIndex = @{}
$userIds = @()

if ($sites -ne "All" -and -not $wildcard) {
    $rootSource = (api get protectionSources/rootNodes?environments=kO365) |
                  Where-Object { $_.protectionSource.name -eq $sourceName }

    if (!$rootSource) {
        Write-Host "O365 Source $sourceName not found" -ForegroundColor Yellow
        exit
    }

    $sitesNode = (api get "protectionSources?id=$($rootSource.protectionSource.id)&excludeOffice365Types=kMailbox,kUser,kGroup,kSite,kPublicFolder,kTeam,kO365Exchange,kO365OneDrive,kO365Sharepoint&allUnderHierarchy=false").nodes |
                 Where-Object { $_.protectionSource.name -eq 'Sites' }

    if (!$sitesNode) {
        Write-Host "Source $sourceName is not configured for M365 Sites" -ForegroundColor Yellow
        exit
    }

    $users = api get "protectionSources?pageSize=$pageSize&nodeId=$($sitesNode.protectionSource.id)&id=$($sitesNode.protectionSource.id)&hasValidSites=true&allUnderHierarchy=false"
    while ($users) {
        foreach ($node in $users.nodes) {
            $nameIndex[$node.protectionSource.name] = $node.protectionSource.id
        }
        $cursor = $users.nodes[-1].protectionSource.id
        $users = api get "protectionSources?pageSize=$pageSize&nodeId=$($sitesNode.protectionSource.id)&id=$($sitesNode.protectionSource.id)&hasValidSites=true&allUnderHierarchy=false&afterCursorEntityId=$cursor"
        if (!$users.PSObject.Properties['nodes'] -or $users.nodes.Count -eq 1) {
            break
        }
    }

    foreach ($site in $sitesToAdd) {
        $userId = if ($nameIndex.ContainsKey($site)) { $nameIndex[$site] } else { $smtpIndex[$site] }
        if ($userId) {
            $userIds += $userId
        } else {
            Write-Host "Site for $site not found" -ForegroundColor Yellow
        }
    }
}
elseif ($wildcard) {
    $protectedSources = (api get -v2 data-protect/search/protected-objects).objects |
                        Where-Object objectType -eq "kSite"

    if (!$protectedSources) {
        Write-Host "No Sites found" -ForegroundColor Yellow
        exit
    }

    foreach ($site in $sitesToAdd) {
        $matchingSites = $protectedSources | Where-Object { $_.name -like "*$site*" }
        if ($matchingSites) {
            $userIds += $matchingSites.id
            Write-Host "Site ID matching $site : $($matchingSites.id)"
        }
    }
}
else {
    $protectedSources = (api get -v2 data-protect/search/protected-objects).objects |
                        Where-Object objectType -eq "kSite"

    if (!$protectedSources) {
        Write-Host "No Sites found" -ForegroundColor Yellow
        exit
    }

    $userIds = $protectedSources | Where-Object { $_.latestSnapshotsInfo -eq 0 } | Select-Object -ExpandProperty id
}

# Configure protection parameters
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

# Protect the sites
foreach ($userId in $userIds) {
    if ($userId) {
        $protectionParams.objects = @(@{
            "environment"     = "kO365Sharepoint";
            "office365Params" = @{
                "objectProtectionType" = "kSharePoint";
                "sharepointSiteObjectProtectionParams" = @{
                    "objects"        = @(@{ "id" = $userId; "shouldAutoProtectObject" = $false });
                    "indexingPolicy" = @{
                        "enableIndexing" = $true;
                        "includePaths"   = @("/");
                        "excludePaths"   = @()
                    }
                }
            }
        })
        Write-Host "Protecting Site for ID $userId"
        $response = api post -v2 data-protect/protected-objects $protectionParams
    } else {
        Write-Host "ID not found" -ForegroundColor Yellow
    }
}
