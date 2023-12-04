# process commandline arguments
[CmdletBinding()]
param (
    [Parameter()][string]$username = 'DMaaS',
    [Parameter(Mandatory = $True)][string]$region,  # CCS region
    [Parameter(Mandatory = $True)][string]$policyName = '',  # protection policy name
    [Parameter(Mandatory = $True)][string]$sourceName,  # name of registered O365 source
    [Parameter()][array]$teams,  # optional names of MS Teams to protect
    [Parameter()][string]$teamsList,  # optional textfile of MS Teams to protect
    [Parameter()][string]$startTime = '20:00',  # e.g. 23:30 for 11:30 PM
    [Parameter()][string]$timeZone = 'America/New_York', # e.g. 'America/New_York'
    [Parameter()][int]$incrementalSlaMinutes = 60,  # incremental SLA minutes
    [Parameter()][int]$fullSlaMinutes = 120,  # full SLA minutes
    [Parameter()][int]$pageSize = 1000
)

$outfileName = ".\log-Protect_CCS_M365Teams-$dateString.txt"

# gather list of MS Teams to protect
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

$teamsToAdd = @($teamsToAdd | Where-Object {$_ -ne ''})

if($teamsToAdd.Count -eq 0){
    Write-Host "No Teams specified" -ForegroundColor Yellow
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

$policy = (api get -mcmv2 data-protect/policies?types=DMaaSPolicy).policies | Where-Object name -eq $policyName
if(!$policy){
    write-host "Policy $policyName not found" -ForegroundColor Yellow
    exit
}

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

$teamsAdded = 0

# find teams
foreach($team in $teamsToAdd){
    $userId = $null
    if($smtpIndex.ContainsKey($team)){
        $userId = $smtpIndex[$team]
    }elseif($nameIndex.ContainsKey($team)){
        $userId = $nameIndex[$team]
    }   
    if($userId){
        $protectionParams.objects = @(@{
            "environment"     = "kO365Teams";
            "office365Params" = @{
                "objectProtectionType"              = "kTeams";
                "teamsObjectProtectionParams" = @{
                    "objects"        = @(
                        @{
                            "id" = $userId
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
        Write-Host "Protecting Team for $team"
        $response = api post -v2 data-protect/protected-objects $protectionParams
	$response | out-file -filepath .\$outfileName -Append
    }else{
        Write-Host "Team for $team not found" -ForegroundColor Yellow
    }
}

