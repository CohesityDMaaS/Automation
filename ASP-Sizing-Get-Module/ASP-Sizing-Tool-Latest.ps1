<# 
.SYNOPSIS
 This tool is PowerShell script that connects to cloud services (M365, Google Workspace etc.) and collects the usage information for various workloads. 
 The size of the data calculated by the script aligns with the data backed up by Cohesity Alta SaaS Protection. At the end of script, all collected information is exported to a CSV file. 

.DESCRIPTION  
 Current release supports sizing of following workloads. 
 
 M365: 
    1. Exchange Online
    2. SharePoint Online
    3. OneDrive for Business
    4. Teams Chat
 Google Workspace:
    1. GMail
    2. Google Drive
 
.INPUTS
 
.OUTPUTS
 1. Output report is generated in CSV format at same location of this script. Report name is 'ASP-Stats- yyyyMMdd-hhmmss.csv'.
 2. Log file is generated at the same location of this script. Log name is 'ASP-Sizing-Tool.log'.

.NOTES
ScriptVersion: 3.7.1

.LINK
 https://www.veritas.com/content/support/en_US/article.100060254 

#>

#----------------------------------------------------------------------------------------------------
# Function to create debug logs at the PowerShell script location.
#----------------------------------------------------------------------------------------------------

function Add-Log
{ 
    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)] [ValidateNotNullOrEmpty()] [Alias("LogContent")] [string]$Message,
        [Parameter(Mandatory=$false)] [Alias('LogPath')] [string]$Path = $global:LogFilePath,          
        [Parameter(Mandatory=$false)] [ValidateSet("Error","Warn","Action","Info", "LogOnly")] [string]$Level="Info",          
        [Parameter(Mandatory=$false)] [switch]$NoClobber=$false 
    ) 
 
    Begin 
    { 
        # Set VerbosePreference to Continue so that verbose messages are displayed. 
        $VerbosePreference = 'Continue' 
    } 
    
    Process 
    {
        if($Path -eq "")
        {
            $ScriptName = ([io.fileinfo]$MyInvocation.MyCommand.ScriptBlock.File).BaseName
		    $LogName = $ScriptName+"-"+$global:date+".log"
            $Path = "${PSScriptRoot}\$LogName"	
        }
        
        # If the file already exists and NoClobber was specified, archive the logs. 
        if((Test-Path $Path) -AND $NoClobber)
        {
            $newLogDate = Get-Date -Format "yyyyMMddHHmmss"
            $OldPath = $Path.Replace(".log",$newLogDate+".log")          
            Rename-Item -Path $Path -NewName $OldPath
        } 
 
        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path. 
        if(!(Test-Path $Path))
        { 
            Write-Verbose "Creating $Path." 
            New-Item $Path -Force -ItemType File | Out-Null
        } 
 
        # Format Date for our Log File 
        $logDate = Get-Date -Format "yyyy-MM-dd HHmmss" 
		$FormattedDate = "[" + $logDate + "]" 
 
        # Write message to error, warning, or verbose pipeline and specify $LevelText 
        switch ($Level) 
        { 
            'Error' { 
                        Write-Host $Message -ForegroundColor Red
                        $LevelText = 'ERROR:' 
                    } 
            'Warn'  { 
                        Write-Host $Message -ForegroundColor Yellow
                        $LevelText = 'WARNING:' 
                    } 
            'Info'  { 
                        Write-Host $Message -ForegroundColor Green
                        $LevelText = 'INFO:' 
                    } 
            'Action'{
                        Write-Host $Message -ForegroundColor Cyan
                        $LevelText = 'ACTION:' 
                    }
            'LogOnly'{
                        $LevelText = 'LOG:'
                    }
        } 
         
        # Write log entry to $Path 
        try
        {
            "$FormattedDate [$env:COMPUTERNAME] $LevelText $Message" | Out-File -FilePath $Path -Append -Encoding ascii            
        }
        catch {}
    }
}

#----------------------------------------------------------------------------------------------------
# Function to log environment check log.
#----------------------------------------------------------------------------------------------------

function Add-EnvCheckLog
{
    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)] [ValidateNotNullOrEmpty()] [Alias("LogContent")] [string]$Message,
        [Parameter(Mandatory=$true)] [ValidateSet("PASS","FAIL","WARN")] [string]$Level
    )

    $totalScreenLength = $Host.UI.RawUI.WindowSize.Width - 10
    $levelText = "[$Level]`n`n"
    $fillText = "-" * $($totalScreenLength - $Message.Length - $levelText.Length)
    
    switch ($Level)
    {
        'PASS'  {
                    Add-Log "$Message$fillText$levelText" -Level Info
                }
        'FAIL'  {
                    Add-Log "$Message$fillText$levelText" -Level Error
                }
        'WARN'  {
                    Add-Log "$Message$fillText$levelText" -Level Warn
                }
    }
}

#----------------------------------------------------------------------------------------------------
# Get the script version
#----------------------------------------------------------------------------------------------------

function Get-ScriptVersion
{
    Param
    (
        [Parameter(ValueFromPipeline=$true)] [ValidateNotNullOrEmpty()] $ScriptPath
    )

    try 
    {
        $verTxt = (get-help -Full $ScriptPath).alertSet.alert.text.ToString()
        $ver = $verTxt -split ': '
        return $ver[1]
    }
    catch 
    {
        return $null
    }
}

#----------------------------------------------------------------------------------------------------
# Download the latest script
#----------------------------------------------------------------------------------------------------

function Test-ScriptVersion
{
    try 
    {
        $currentVersion = Get-ScriptVersion -ScriptPath "$($MyInvocation.ScriptName)"

        # Get latest version number from download location
        $scriptUrl = "https://nspartifacts.blob.core.windows.net/prod/ASP-Sizing-Tool.ps1"
        $latestScriptString = Invoke-WebRequest $scriptUrl
        $latestVersionString = $([Regex]::Matches($latestScriptString.RawContent, "Version: [\d\.]+\s"))[0].Value.ToString()
        $latestVersionValues = $latestVersionString -split ': '
        $latestVersion = $latestVersionValues[1].Trim()

        if([System.Version]$latestVersion -gt [System.Version]$currentVersion)
        {
            Add-Log "`nThis script is running older version [$currentVersion]. Latest version of script [$latestVersion] is available for download." -Level Warn
            Add-Log "`nIt is recommeneded to use the latest version of the script for sizing." -Level Warn
            Add-Log "`nDo you want to download the latest version [$latestVersion] of the script : [Y] Yes [N] No (Default: [Y])" -Level Action
            $downloadInput = Read-Host "Enter your choice"
            if($downloadInput -match "[nN]")
            {
                Add-Log "`nProceeding with current version [$currentVersion]." -Level Warn
            }
            else
            {
                # Download the latest version of the script
                $scriptLatest = "${PSScriptRoot}\ASP-Sizing-Tool-Latest.ps1"
                Start-BitsTransfer -Source $scriptUrl -Destination $scriptLatest       
                
                Add-Log "`nPlease run the latest version of the script downloaded at the location $([char]27)[4m$scriptLatest$([char]27)[24m. This script will now exit."
                Pause
                exit
            }
        }
        else
        {
            Add-Log "`nYou are running the latest version [$latestVersion] of the script."
        }
    }
    catch
    {
        Add-Log "Unable to connect to server to get latest version of script. Proceeding with current version [$currentVersion]." -Level Warn
    }
}

#----------------------------------------------------------------------------------------------------
# Print the script version information
#----------------------------------------------------------------------------------------------------

function Write-ScriptInfo
{
    $versionTxt = (get-help -Full "$($MyInvocation.ScriptName)").alertSet.alert.text.ToString()
    $version = $versionTxt -split ': '
    $scriptVersion = "ASP Sizing Tool. Version : [" + $version[1] + "]"
    $x = $Host.UI.RawUI.WindowSize.Width -2
    $y = $scriptVersion.Length
    $header = "#" + " " * $($($x -$y)/2) + $scriptVersion + " " * $($x -$y -$($($x -$y)/2)) + "#"
    $headerline = "#" + "-" * $($Host.UI.RawUI.WindowSize.Width -2) + "#"

    Add-Log "`n$headerLine"
    Add-Log "$header"
    Add-Log "$headerLine"
}

#----------------------------------------------------------------------------------------------------
# Function to add statistics for individual workloads.
#----------------------------------------------------------------------------------------------------

function Add-Stats
{ 
    Param 
    ( 
        [Parameter(Mandatory=$true)] [string]$Category,
        [Parameter(Mandatory=$false)] [string]$ObjectType,
        [Parameter(Mandatory=$false)] [string]$ObjectCount,
        [Parameter(Mandatory=$false)] [string]$ItemCount,
        [Parameter(Mandatory=$false)] [string]$ItemSize,
        [Parameter(Mandatory=$false)] [string]$RecoverableItemCount,
        [Parameter(Mandatory=$false)] [string]$RecoverableItemSize,
        [Parameter(Mandatory=$false)] [string]$TotalItemCount,
        [Parameter(Mandatory=$false)] [string]$TotalItemSize,
        [Parameter(Mandatory=$false)] [string]$EffectiveItemSize,
        [Parameter(Mandatory=$false)] [string]$DataGrowth,
        [Parameter(Mandatory=$false)] [string]$GrowthRate
    ) 

    $stats = New-Object PSObject
    $stats | Add-Member -MemberType NoteProperty -Name 'Workload' -Value $Category
    $stats | Add-Member -MemberType NoteProperty -Name 'Type' -Value $ObjectType
    $stats | Add-Member -MemberType NoteProperty -Name 'Count' -Value $ObjectCount
    $stats | Add-Member -MemberType NoteProperty -Name 'Item Count' -Value $ItemCount
    $stats | Add-Member -MemberType NoteProperty -Name 'Item Size (GiB)' -Value $ItemSize
    $stats | Add-Member -MemberType NoteProperty -Name 'Recoverable Item Count' -Value $RecoverableItemCount
    $stats | Add-Member -MemberType NoteProperty -Name 'Recoverable Item Size (GiB)' -Value $RecoverableItemSize
    $stats | Add-Member -MemberType NoteProperty -Name 'Total Item Count' -Value $TotalItemCount
    $stats | Add-Member -MemberType NoteProperty -Name 'Total Item Size (GiB)' -Value $TotalItemSize
    $stats | Add-Member -MemberType NoteProperty -Name 'Effective Size in ASP (GiB)' -Value $EffectiveItemSize
    $stats | Add-Member -MemberType NoteProperty -Name 'Data Growth over last 180 days(GiB)' -Value $DataGrowth
    $stats | Add-Member -MemberType NoteProperty -Name 'Growth Rate over last 180 days(%)' -Value $GrowthRate
    return $stats
}

#----------------------------------------------------------------------------------------------------
# Function to convert size from bytes to human readable format.
#----------------------------------------------------------------------------------------------------

function Format-Bytes 
{
    Param
    (
        [Parameter(ValueFromPipeline=$true)] [ValidateNotNullOrEmpty()] $Number,
        [Parameter(Mandatory=$false)] [ValidateSet("Bytes","KiB","MiB","GiB","TiB","PiB")] [string]$Unit
    )
    Begin
    {
    }
    Process 
    {
        if([string]::IsNullOrEmpty($Unit))
        {
            if($Number -lt 1024) {$Unit = "Bytes"}
            if(($Number -ge 1Kb) -and ($Number -lt 1Mb)) {$Unit = "KiB"}
            if(($Number -ge 1Mb) -and ($Number -lt 1Gb)) {$Unit = "MiB"}
            if(($Number -ge 1Gb) -and ($Number -lt 1Tb)) {$Unit = "GiB"}
            if(($Number -ge 1Tb) -and ($Number -lt 1Pb)) {$Unit = "TiB"}
            if( $Number -ge 1Pb) {$Unit = "PiB"}
        }
        Switch ($Unit)
        {
            "Bytes" { $num = $Number }
            "KiB" {$num = $Number/1Kb}
            "MiB" {$num = $Number/1Mb}
            "GiB" {$num = $Number/1Gb}
            "TiB" {$num = $Number/1Tb}
            "PiB" {$num = $Number/1Pb}
        }
        $num = "{0:f3}" -f $num
        $outNum = [System.Convert]::ToDecimal($num)
        return $outNum
    }
    End{}
}

#----------------------------------------------------------------------------------------------------
# Environment Check : Check for module availability
#----------------------------------------------------------------------------------------------------

function Test-PSMOdule
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory=$true)][String]$Name,
        [Parameter(Mandatory=$false)] [System.Version]$MinVer,
        [Parameter(Mandatory=$false)] [System.Version]$MaxVer,
        [Parameter(Mandatory=$false)] [System.Version]$Exact,
        [Parameter(Mandatory=$false)] [switch]$MustNotExist=$false
    )

    $flag = $true
    $modules = @()
    $modules += Get-InstalledModule -Name $Name -AllVersions -ErrorAction SilentlyContinue
    
    $requiredVersionString = "Supported version for $Name : "
    if($null -ne $MinVer)
    {
        $requiredVersionString += "[Minimum: $($MinVer.ToString())] "
    }
    if($null -ne $MaxVer)
    {
        $requiredVersionString += "[Maximum: $($maxVer.ToString())]"
    }
    elseif ($null -ne $Exact) 
    {
        $requiredVersionString += "[Exact: $Exact]"
    }
    elseif($MustNotExist)
    {
        $requiredVersionString = "Module $Name must NOT exist on the system."
    }

    if($modules.Count -eq 0)
    {
        if(-not $MustNotExist)
        {
            Add-Log "Required PowerShell Module NOT installed : $Name" -Level Error
            $flag = $false
        }
        else 
        {
            Add-Log "Unsupported PowerShell Module NOT installed : $Name"
        }
    }
    else
    {
        foreach($module in $modules)
        {
            if ($null -ne $Exact)
            {
                if($module.Version -ne $Exact)
                {
                    Add-Log "Unsupported PowerShell Module Found : $($module.Name) [Version: $($module.Version)]" -Level Error
                    $flag = $false
                }
            }
            elseif ($MustNotExist) 
            {
                Add-Log "Unsupported PowerShell Module Found : $($module.Name) [Version: $($module.Version)]" -Level Error
                $flag = $false
            }
            else 
            {
                if(($null -ne $MinVer) -and ($null -eq $MaxVer))
                {
                    if($module.Version -lt $MinVer)
                    {
                        $flag = $false
                    }
                }
                elseif(($null -eq $MinVer) -and ($null -ne $MaxVer))
                {
                    if($module.Version -gt $MaxVer)
                    {
                        $flag = $false
                    }
                }
                elseif(($null -ne $MinVer) -and ($null -ne $MaxVer))
                {
                    if(($module.Version -lt $MinVer) -or ($module.Version -gt $MaxVer))
                    {
                        $flag = $false
                    }                
                }
                if(-not $flag)
                {
                    Add-Log "Unsupported PowerShell Module Found : $($module.Name) [Version: $($module.Version)]" -Level Error
                }
            }
            
            if($flag)
            {
                Add-Log "Required PowerShell Module Found : $($module.Name) [Version: $($module.Version)]"
            }
        }
    }
    if($flag)
    {
        Add-EnvCheckLog "Environment check for module $Name :" -Level PASS
    }
    else 
    {
        Add-Log "$requiredVersionString" -Level Warn
        Add-EnvCheckLog "Environment check for module $Name :" -Level FAIL
        $global:EnvironmentCheckStatus = $false
    }

    return $flag
}

#----------------------------------------------------------------------------------------------------
# Environment Check : Sizing Tool environment check method
#----------------------------------------------------------------------------------------------------

function Test-Environment
{
    $global:EnvironmentCheckStatus = $true

    Add-Log "`nStarting environment check based on the options selected for sizing..."

    # Check PowerShell Version
    if($PSVersionTable.PSVersion -ge 5.2)
    {
        Add-Log "`nPowerShell Version on System [$($PSVersionTable.PSVersion)]" -Level Error
        Add-EnvCheckLog "Environment check for PowerShell Version :" -Level FAIL
        $global:EnvironmentCheckStatus = $false
    }
    else 
    {
        Add-Log "`n`nPowerShell Version on System [$($PSVersionTable.PSVersion)]"
        Add-EnvCheckLog "Environment check for PowerShell Version :" -Level PASS
    }

    # Check Modules Microsoft.Graph, ExchangeOnlineManagement, ThreadJob, SharePointPnPPowerShellOnline, PnP.PowerShell
    
    Test-PSMOdule -Name Microsoft.Graph -MinVer 2.19.0 | Out-Null

    if($global:ProcessExchange)
    {
        Test-PSMOdule -Name ExchangeOnlineManagement -MinVer 3.5.1 | Out-Null
        Test-PSMOdule -Name ThreadJob -MinVer 2.0.3 | Out-Null
    }
    if($global:ProcessSharePoint -or $global:ProcessOneDrive)
    {
        Test-PSMOdule -Name SharePointPnPPowerShellOnline -MinVer 3.29.2101.0 | Out-Null
        Test-PSMOdule -Name PnP.PowerShell -MustNotExist | Out-Null 
    }
    if(-not $global:EnvironmentCheckStatus)
    {
        Add-Log "Environment check failed for selected options for sizing. Please install required modules and re-run this script. This script will now exit.`n" -Level Error
        Pause
        exit
    }

    Add-Log "Environment check is successful for the options selected for sizing.`n"
}

#----------------------------------------------------------------------------------------------------
# Select which option to process for sizing
#----------------------------------------------------------------------------------------------------

function Select-SizingOption
{
    Add-Log "`nSelect one of the following options to start sizing tool.`n`t[1] M365`n`t[2] Google" -Level Action
    $scriptInput = Read-Host "Enter your choice"
    if($scriptInput -eq '1')
    {
        $global:ProcessM365 = $true
    }
    elseif($scriptInput -eq '2')
    {
        $global:ProcessGoogle = $true
    }
    else 
    {
        Add-Log "Incorrect input. exiting.." -Level Error
        exit
    }
}

#----------------------------------------------------------------------------------------------------
# Select M365 workloads to process
#----------------------------------------------------------------------------------------------------

function Select-M365Options
{
    Add-Log "`nDo you want to collect statistics for Exchange Online: [Y] Yes [N] No (Default: [Y])" -Level Action
    $exoInput = Read-Host "Enter your choice"
    if($exoInput -match "[nN]")
    {
        $global:ProcessExchange = $false
    }
    Add-Log "`nDo you want to collect statistics for SharePoint Online: [Y] Yes [N] No (Default: [Y])" -Level Action
    $spoInput = Read-Host "Enter your choice"
    if($spoInput -match "[nN]")
    {
        $global:ProcessSharePoint = $false
    }
    Add-Log "`nDo you want to collect statistics for OneDrive for Business: [Y] Yes [N] No (Default: [Y])" -Level Action
    $odbInput = Read-Host "Enter your choice"
    if($odbInput -match "[nN]")
    {
        $global:ProcessOneDrive = $false
    }
    Add-Log "`nDo you want to collect statistics for Teams Chat: [Y] Yes [N] No (Default: [Y])" -Level Action
    $tcInput = Read-Host "Enter your choice"
    if($tcInput -match "[nN]")
    {
        $global:ProcessTeamsChat = $false
    }
    if($global:ProcessSharePoint -or $global:ProcessOneDrive)
    {
        Add-Log "`nEnter the SharePoint Online admin url. Usually in the form https://<tenant>-admin.sharepoint.com" -Level Action
        $global:SPOAdminUrl = Read-Host "Enter the admin URL"
    }
    if($global:ProcessExchange -or $global:ProcessOneDrive)
    {
        Add-Log "`nDo you want to limit the scope of Exchange Online and OneDrive to users in a specific AD group: [Y] Yes [N] No (Default: [N])" -Level Action
        $grpInput = Read-Host "Enter your choice"
        if($grpInput -match "[yY]")
        {
            $global:LimitScopeToADGroup = $true
            $global:ADGroup = Read-Host "Enter the one or more AD group display names separated by comma"
        }
    }
}

#----------------------------------------------------------------------------------------------------
# Select M365 authentication mode
#----------------------------------------------------------------------------------------------------

function Select-M365AuthMode
{
    Add-Log "`nSelect the authentication mode: `n`tUser Login`t[1] `n`tApplication`t[2] `n`tCustomApp`t[3]" -Level Action
    do
    {
        $authInput = Read-Host "Select Authentication Mode"
    }
    while(($authInput -ne '1') -and ($authInput -ne '2') -and ($authInput -ne '3'))
    if($authInput -eq '1')
    {
        $global:AuthMode = 'UserLogin'
        Add-Log "UserLogin authentication mode selected for running the script."
    }
    elseif($authInput -eq '2')
    {
        $global:AuthMode = 'Application'
        Add-Log "Application authentication mode selected for running the script."
    }
    elseif ($authInput -eq '3') 
    {
        $global:AuthMode = 'CustomApp'
        Add-Log "CustomApp authentication mode selected for running the script."
    }
}

#----------------------------------------------------------------------------------------------------
# Funtion to connect to microsoft graph.
#----------------------------------------------------------------------------------------------------

function Connect-MicrosoftGraph
{
    try 
    {
        Add-Log "Connecting to Microsoft Graph.."

        if($global:AuthMode -eq 'CustomApp')
        {
            Connect-MgGraph -TenantId $global:TenantId -ClientId $global:AppID -CertificateThumbprint $global:AppThumbprint -NoWelcome -ErrorAction Stop | Out-Null
        }
        else 
        {
            Connect-MgGraph -Scopes @("Application.ReadWrite.All, Reports.Read.All, User.Read.All, Directory.Read.All, Organization.Read.All") -NoWelcome -ErrorAction Stop | Out-Null

            $global:TenantId = (Get-MgContext).TenantId
    
            $global:AzOrg = (Get-MgOrganization | Select-Object -ExpandProperty VerifiedDomains | Where-Object {$_.IsDefault -eq 'True'}).Name
        }
    }
    catch
    {
        $exception = $_.Exception.Message
        Add-Log "Failed to connect to Microsoft Graph with following error: $exception. `nThis script will now exit." -Level Error
        exit
    }
    Add-Log "Successfully connected to Microsoft Graph."
}

#----------------------------------------------------------------------------------------------------
# Function to connect to Exchange Online
#----------------------------------------------------------------------------------------------------

function Connect-Exchange
{
    # Get certification to connect to the application
    if(($global:AuthMode -eq 'Application') -or ($global:AuthMode -eq 'CustomApp'))
    {
        $certificate = Get-ChildItem -path Cert:\CurrentUser\my | Where-Object { $PSitem.Thumbprint -eq $global:AppThumbprint }
    }

    # Connect to Exchange Online
    Add-Log "Connecting to Exchange Online.."
    try
    {
        if($global:AuthMode -eq 'UserLogin')
        {
            Connect-ExchangeOnline -Credential $global:Credentials -ShowBanner:$false -ErrorAction Stop
        }
        else 
        {
            Connect-ExchangeOnline -AppId $global:AppID -Certificate $certificate -Organization  $global:AzOrg -ShowBanner:$false -ErrorAction Stop
        }
    }
    catch
    {
        $exception = $_.Exception.Message
        Add-Log "Failed to connect to Exchange Online with following error : $exception" -Level Error
        Add-Log "Retry using interactive login.."
        try
        {
            Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
        }
        catch
        {
            $exception = $_.Exception.Message
            Add-Log "Failed to connect to Exchange Online with error: $exception. Skipping Exchange Online statistics collection." -Level Error
            return
        }
    }
    Add-Log "Successfully connected to Exchange Online."
}

#----------------------------------------------------------------------------------------------------
# Function to connect to SharePoint Online
#----------------------------------------------------------------------------------------------------

function Connect-SharePoint
{
    Param 
    ( 
        [Parameter(Mandatory=$true)][string]$AdminUrl
    ) 

    if(($global:AuthMode -eq 'Application') -or ($global:AuthMode -eq 'CustomApp'))
    {
        $certificate = Get-ChildItem -path Cert:\CurrentUser\my | Where-Object { $PSitem.Thumbprint -eq $global:AppThumbprint }
    }

    # Connect to SharePoint Online
    Add-Log "Connecting to SharePoint Online.."
    try 
    {
        if($global:AuthMode -eq 'UserLogin')
        {
            Connect-PnPOnline -Url $AdminUrl -Credentials $global:Credentials -WarningAction Ignore -ErrorAction Stop
        }
        else 
        {
            Connect-PnPOnline -Url $AdminUrl -Tenant $global:TenantId -ClientId $global:AppID -Certificate $certificate -WarningAction Ignore -ErrorAction Stop    
        }                 
    }
    catch 
    {
        $exception = $_.Exception.Message
        Add-Log "Failed to connect to SharePoint Online with following error : $exception." -Level Error
        Add-Log "Retry using interactive login.."
        try 
        {
            Connect-PnPOnline -Url $AdminUrl -UseWebLogin -WarningAction Ignore -ErrorAction Stop
        }
        catch 
        {
            $exception = $_.Exception.Message
            Add-Log "Failed to connect to SharePoint Online with following error : $exception. `nSkipping SharePoint Online statistics collection." -Level Error
            return
        }
    }
    Add-Log "Successfully connected to SharePoint Online."
}

#----------------------------------------------------------------------------------------------------
# Funtion to get data growth rate over 180 days for individual workload.
#----------------------------------------------------------------------------------------------------

function Get-GrowthRate
{
    Param 
    ( 
        [Parameter(Mandatory=$true)] [ValidateSet("Exchange","SharePoint","OneDrive")] [string]$Type 
    ) 
  
    $usageStatsFile = "${PSScriptRoot}\$Type-GrowthRate-$global:date.csv"
    Add-Log "Getting the data growth rate for $Type."
    try 
    {
        Connect-MicrosoftGraph

        switch ($Type) 
        {
            "Exchange" 
            {
                Get-MgReportMailboxUsageStorage -Period "D180" -OutFile $usageStatsFile -PassThru -ErrorAction Stop  
            }
            "SharePoint"
            {
                Get-MgReportSharePointSiteUsageStorage -Period "D180" -OutFile $usageStatsFile -PassThru -ErrorAction Stop
            }
            "OneDrive"
            {
                Get-MgReportOneDriveUsageStorage -Period "D180" -OutFile $usageStatsFile -PassThru -ErrorAction Stop
            }
        }
    }
    catch 
    {
        $exception = $_.Exception.Message
        Add-Log "Failed to get usage statistics for $Type for last 180 days with following exception: $exception" -Level Error
        return "Data Unavailable", "Data Unavailable" 
    }
    
    # Read downloaded csv file
    $usageCsv = Import-Csv $usageStatsFile
    
    # If csv file doesnt contain any data then return null
    if($usageCsv.Count -eq 0)
    {
        return "Data Unavailable", "Data Unavailable"
    }

    # Calculate data growth rate
    $CurrentSize = $usageCsv[0].("Storage Used (Byte)")
    $days = 0
    foreach($item in $usageCsv)
    {
        if([string]::IsNullOrEmpty($item.("Storage Used (Byte)")))
        {
            # If data is empty in the output then skip
            continue
        }
        elseif (($Type -eq "OneDrive") -and ($item.("Site Type") -eq "All")) 
        {
            # For OneDrive only check for 'OneDrive' type and skip 'All' type rows
            continue
        }
        else
        {
            # Get the data if output is not empty
            $PreviousSize = ($item.("Storage Used (Byte)"))
            $days++
        }
    }

    $numDays = [System.Convert]::ToInt32($days)
    $sizeGrowth = $CurrentSize - $PreviousSize
    if($numDays -lt 180)
    {
        $sizeGrowth = ($sizeGrowth * 180) / $numDays
    }
    $percentageGrowth = [math]::round(($sizeGrowth*100)/$PreviousSize,2)
    $sizeGrowthGB = Format-Bytes $sizeGrowth GiB
    $growthStat = $sizeGrowthGB, "$percentageGrowth`%"
    Remove-Item -Path $usageStatsFile -Force -Confirm:$false
    Add-Log "Projected data growth for $Type is $sizeGrowthGB GiB over 180 days based on data received for last $days days."
    
    return $growthStat
}

#----------------------------------------------------------------------------------------------------
# Function to create app registration
#----------------------------------------------------------------------------------------------------

function New-AppReg
{
    try
    {
        # Create new azude ad application
        Add-Log "Creating new application in AAD with name: $global:AppName"
        $app = New-MgApplication -DisplayName $global:AppName -Description "Application Created for ASP Sizing Tool"
        
        New-MgServicePrincipal -AppId $app.AppId -AdditionalProperties @{} | Out-Null

        # Adding credentials (certificate) to application 
        $NotAfter = (Get-Date).AddMonths(1)
        $cert = New-SelfSignedCertificate -CertStoreLocation "cert:\CurrentUser\My" -Subject "CN=$global:AppName" -KeySpec Signature -NotAfter $NotAfter -KeyExportPolicy Exportable
        Update-MgApplication -ApplicationId $app.Id -KeyCredentials @{Type="AsymmetricX509Cert";Usage="Verify";Key=$cert.RawData;}

        $global:AppThumbprint = $cert.Thumbprint

        $requiredResourceAccess = @()

        # Adding permissions required for reading the data growth reports
        $requiredResourceAccessGraph = @{
            ResourceAppId = "00000003-0000-0000-c000-000000000000";
            ResourceAccess = @(
                @{
                    # Microsoft Graph > Reports.Read.All - Application
                    Id = "230c1aed-a721-4c5d-9cb4-a90514e508ef";
                    Type = "Role"
                },
                @{
                    # Microsoft Graph > User.Read.All - Application
                    Id = "df021288-bdef-4463-88db-98f22de89214";
                    Type = "Role"
                }
            )
        }
        $requiredResourceAccess += $requiredResourceAccessGraph

        # Adding permissions required for getting the list of all sites and get usage information.
        if($global:ProcessSharePoint -or $global:ProcessOneDrive)
        {
            $requiredResourceAccessSharePoint = @{
                ResourceAppId = "00000003-0000-0ff1-ce00-000000000000";
                ResourceAccess = @(
                    @{
                        # Sharepoint > Sites.FullControl.All - Application
                        Id = "678536fe-1083-478a-9c59-b99265e6b0d3";
                        Type = "Role"
                    },
                    @{
                        # Sharepoint > User.Read.All - Application
                        Id = "df021288-bdef-4463-88db-98f22de89214";
                        Type = "Role"
                    }
                )
            }
            $requiredResourceAccess += $requiredResourceAccessSharePoint
        }

        # Adding permissions required for getting the list of user and group mailboxes, public folders and their usage statistics.
        if($global:ProcessExchange)
        {
            $requiredResourceAccessExchange = @{
                ResourceAppId = "00000002-0000-0ff1-ce00-000000000000";
                ResourceAccess = @(
                    @{
                        # Office 365 Exchange Online > Exchange.ManageAsApp - Application
                        Id = "dc50a0fb-09a3-484d-be87-e023b12c6440";
                        Type = "Role"
                    }
                )
            }
            $requiredResourceAccess += $requiredResourceAccessExchange
        }
        
        Update-MgApplication -ApplicationId $app.Id -RequiredResourceAccess $requiredResourceAccess
    }
    catch
    {
        $exception = $_.Exception.Message
        Add-Log "Failed to create application registration with required permissions with following exception: $exception." -Level Error
        Add-Log "Make sure that logged in user has appropriate permissions to create the application in azure active directory. This script will now exit." -Level Error
        Pause
        exit
    }
    # Grant admin consent to the app created.
    $global:AppID = $app.AppId
    Add-Log "Following app is created in AAD. `n`t 1. Grant the admin consent to this app." -Level Action
    if($global:ProcessExchange)
    {
        Add-Log "`t 2. Assign Exchange Administrator role to this app." -Level Action
    }
    Add-Log "App Display Name: $global:AppName, App Client Id: $($global:AppID)" -Level Action 
    Pause
    Add-Log "Is admin consent given to app $global:AppName ? Grant admin consent and then enter [Y] to continue.." -Level Action
    do
    {
        $consentGranted = Read-Host "Admin Consent Granted?"
    }
    while($consentGranted -notmatch "[yY]")
}

#----------------------------------------------------------------------------------------------------
# Function to get licensed M365 users. 
#----------------------------------------------------------------------------------------------------

function Get-M365LicensedUsers
{
    try 
    {
        Connect-MicrosoftGraph
        Add-Log "Getting the number of licensed users in this M365 tenant."
        $licensedUsers = 0
        $allUsers = Get-MgUser -All -property DisplayName,UserPrincipalName,AssignedPlans
        foreach($user in $allUsers) 
        {
            $plans = $user.AssignedPlans
            foreach($plan in $plans)
            {
                if((($plan.Service -eq 'exchange' -or $plan.Service -eq 'sharepoint')) -and ($plan.CapabilityStatus -eq 'Enabled'))
                {
                    $licensedUsers++
                    break
                }
            }
        }
        Add-Log "Found $licensedUsers licensed users in M365 tenant."
        return $licensedUsers
    }
    catch 
    {
        $exception = $_.Exception.Message
        Add-Log "Failed to get licensed users in M365 tenant with following error: $exception." -Level Error
    }
}

#----------------------------------------------------------------------------------------------------
# Function to get statistics data for list of mailboxes.
#----------------------------------------------------------------------------------------------------

function Get-ExchangeMailboxStats
{
    Param 
    ( 
        [Parameter(Mandatory=$true)][Object[]]$Mailboxes,
        [Parameter(Mandatory=$false)][switch]$ProcessArchive=$false
    ) 

    $itemCount = 0
    $itemSizeBytes = 0
    $recoverableItemCount = 0 
    $recoverableItemSizeBytes  = 0

    foreach ($mailbox in $Mailboxes)
    {
        $mailboxStats = $null

        # Get statistics for active mailbox
        try 
        {
            if($ProcessArchive)
            {
                $mailboxStats = Get-EXOMailboxStatistics -IncludeSoftDeletedRecipients -Identity $mailbox.DistinguishedName -Archive -ErrorAction Stop
            }
            else 
            {
                $mailboxStats = Get-EXOMailboxStatistics -IncludeSoftDeletedRecipients -Identity $mailbox.DistinguishedName -ErrorAction Stop
            }           
        }
        catch 
        {
            $exception = $_.Exception.Message
            Add-Log "Failed to get statistics for: $mailbox" -Level Warn
            Add-log "Exception: $exception" -Level LogOnly
            Continue
        }
        
        if($null -eq $mailboxStats)
        {
            Add-Log "Mailbox statistics returned null for: $mailbox" -Level Warn
            Continue
        }

        $itemCount += $mailboxStats.ItemCount
        $itemSizeBytes  += $mailboxStats.TotalItemSize.Value.ToBytes()

        $recoverableItemCount += $mailboxStats.DeletedItemCount
        $recoverableItemSizeBytes  += $mailboxStats.TotalDeletedItemSize.Value.ToBytes()

        $mlbSize = Format-Bytes($mailboxStats.TotalItemSize.Value.ToBytes() + $mailboxStats.TotalDeletedItemSize.Value.ToBytes()) GiB

        Add-Log "Mailbox: $mailbox, Primary Mailbox Size: $mlbSize GiB." -Level LogOnly
    }

    return [PSCustomObject]@{
        ItemCount = $itemCount
        ItemSize = $itemSizeBytes
        RecoverableItemCount = $recoverableItemCount
        RecoverableItemSize = $recoverableItemSizeBytes
    }
}

#----------------------------------------------------------------------------------------------------
# Split the number of mailboxes in different groups for thread jobs.
#----------------------------------------------------------------------------------------------------

function Split-ExchangeMailboxList
{
    Param 
    ( 
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][Object[]]$Mailboxes
    )

    $numOfThreads = 10
    $mbsPerThread = [Math]::Ceiling($Mailboxes.Count / $numOfThreads)
    if(0 -eq $mbsPerThread)
    {
        $mbsPerThread = 1
    }
    $counter = @{ Value = 0 }
    $MailboxesGroups = $Mailboxes | Group-Object -Property { [math]::Floor($counter.Value++ / $mbsPerThread) }

    return $MailboxesGroups
}

#----------------------------------------------------------------------------------------------------
# Function to get list of different types of mailboxes and create thread jobs for stats collection.
#----------------------------------------------------------------------------------------------------

function Start-ExchangeThreadJobs
{
    Param 
    ( 
        [Parameter(Mandatory=$true)][ValidateSet("User","SoftDeleted","Group","PublicFolder","ADGroupUsers")] [string]$ExoMode,
        [Parameter(Mandatory=$false)][string]$ADGroupToProcess
    ) 

    # Variables for Exchange Online session timeout
    $exoSessionTimeout = $global:M365SessionTimeOut - 1
    $exoSessionStartTime = Get-Date
    $exoSessionRefreshTime = $exoSessionStartTime.AddHours($exoSessionTimeout)

    # Variable for final output
    $exchangeOutput = @()

    # Connect to Exchange Online
    Connect-Exchange
    
    $allMailboxes = @()
    $allArchiveMailboxes = @()

    $activeItemCount = 0
    $activeItemsSizeBytes = 0
    $recoverableItemsCount = 0 
    $recoverableItemsSizeBytes  = 0
    $archiveItemsCount = 0 
    $archiveItemsSizeBytes  = 0
    $archiveRecoverableItemsCount = 0
    $archiveRecoverableItemsSizeBytes  = 0

    # Get list of all user mailboxes
    Add-Log "Getting the list of all $ExoMode mailboxes in the tenant."

    if($ExoMode -eq 'User')
    {
        $allMailboxes += Get-EXOMailbox -Resultsize Unlimited

        $allArchiveMailboxes += Get-EXOMailbox -ResultSize Unlimited -Archive
    }
    if($ExoMode -eq 'SoftDeleted')
    {
        $allMailboxes += Get-Mailbox -ResultSize Unlimited -SoftDeletedMailbox -InactiveMailboxOnly

        $allArchiveMailboxes += Get-Mailbox -ResultSize Unlimited -SoftDeletedMailbox -InactiveMailboxOnly -Archive
    }
    if($ExoMode -eq 'Group')
    {
        $allMailboxes += Get-EXORecipient -ResultSize Unlimited -RecipientTypeDetails GroupMailbox
        $allArchiveMailboxes += Get-Mailbox -ResultSize Unlimited -GroupMailbox -Archive
    }
    if($ExoMode -eq 'PublicFolder')
    {
        $allMailboxes += Get-Mailbox -ResultSize Unlimited -PublicFolder
    }
    if($ExoMode -eq 'ADGroupUsers')
    {
        try 
        {          
            $adGroupUsers = @()
            
            $allADGroups = $ADGroupToProcess.Split(',')

            foreach($group in $allADGroups)
            {
                $adgroup = Get-MgGroup -Filter "DisplayName eq '$group'" -ErrorAction Stop
                $adGroupUsers += Get-MgGroupMember -GroupId $adgroup.Id -All -ErrorAction Stop
            }

            # Combined list of users from multiple groups might have duplicate users. So Getting unique entries only.
            $uniqueAdGroupUsers = $adGroupUsers | Sort-Object -Property Id -Unique
        }
        catch
        {
            $exception = $_.Exception.Message
            Add-Log "Failed to get the users from group $group." -Level Error
            Add-log "Exception: $exception" -Level LogOnly
        }

        foreach ($adGroupUser in $uniqueAdGroupUsers)
        {
            try 
            {
                $allMailboxes += Get-EXOMailbox -Identity $adGroupUser.Id -ErrorAction Stop
                $allArchiveMailboxes += Get-EXOMailbox -Identity $adGroupUser.Id -Archive -ErrorAction Stop
            }
            catch 
            {
                $exception = $_.Exception.Message
                Add-Log "Failed to get the mailbox properties for user $($adGroupUser.AdditionalProperties["displayName"])." -Level Error
                Add-log "Exception: $exception" -Level LogOnly
            }
        }
    }

    $allMailboxesCount = @($allMailboxes).Count
    $allArchiveMailboxesCount = @($allArchiveMailboxes).Count

    Add-Log "$ExoMode Mailbox Count : $allMailboxesCount, $ExoMode Archive Mailbox Count : $allArchiveMailboxesCount"

    $allMailboxesGroupList = Split-ExchangeMailboxList -Mailboxes $allMailboxes
    $allArchiveMailboxesGroupList = Split-ExchangeMailboxList -Mailboxes $allArchiveMailboxes

    $def = @(
                ${function:Get-ExchangeMailboxStats}.ToString()
                ${function:Add-Log}.ToString()
                ${function:Format-Bytes}.ToString()
            )

    Add-Log "Getting the size of all $ExoMode primary mailboxes."
    
    $jobs = foreach($group in $allMailboxesGroupList)
    {
        $logFilePath = $global:LogFilePath
        $mbs = $group.Group
        Start-ThreadJob -ScriptBlock {
            $getMailboxStats,$addLog,$formatBytes = $using:def
            ${function:Get-ExchangeMailboxStats} = $getMailboxStats
            ${function:Add-Log} = $addLog
            ${function:Format-Bytes} = $formatBytes
            $global:LogFilePath = $using:logFilePath
            Get-ExchangeMailboxStats -Mailboxes $using:mbs
        }
    }
    if($null -ne $jobs)
    {
        $activeOutput = Receive-Job -Job $jobs -Wait
    
        foreach($activeOut in $activeOutput)
        {
            $activeItemCount += $activeOut.ItemCount
            $activeItemsSizeBytes += $activeOut.ItemSize
            $recoverableItemsCount += $activeOut.RecoverableItemCount
            $recoverableItemsSizeBytes  += $activeOut.RecoverableItemSize
        }
    }
   
    Add-Log "Completed statistics collection for all $ExoMode primary mailboxes."

    Add-Log "Getting the size of all $ExoMode archive mailboxes."

    $archiveJobs = foreach($archiveGroup in $allArchiveMailboxesGroupList)
    {
        $logFilePath = $global:LogFilePath
        $archiveMbs = $archiveGroup.Group
        Start-ThreadJob -ScriptBlock {
            $getMailboxStats,$addLog,$formatBytes = $using:def
            ${function:Get-ExchangeMailboxStats} = $getMailboxStats
            ${function:Add-Log} = $addLog
            ${function:Format-Bytes} = $formatBytes
            $global:LogFilePath = $using:logFilePath
            Get-ExchangeMailboxStats -Mailboxes $using:archiveMbs -ProcessArchive
        }
    }
    if($null -ne $archiveJobs)
    {
        $archiveOutput = Receive-Job -Job $archiveJobs -Wait

        foreach($archiveOut in $archiveOutput)
        {   
            $archiveItemsCount += $archiveOut.ItemCount
            $archiveItemsSizeBytes += $archiveOut.ItemSize
            $archiveRecoverableItemsCount += $archiveOut.RecoverableItemCount
            $archiveRecoverableItemsSizeBytes += $archiveOut.RecoverableItemSize
        }
    }

    Add-Log "Completed statistics collection for all $ExoMode archive mailboxes."

    # Generate statistics output for active mailboxes
    $exchangeOutput += Add-Stats -Category " " `
    -ObjectType "$ExoMode Active Mailboxes" `
    -ObjectCount $allMailboxesCount `
    -ItemCount $activeItemCount `
    -ItemSize (Format-Bytes($activeItemsSizeBytes) GiB) `
    -RecoverableItemCount $recoverableItemsCount `
    -RecoverableItemSize (Format-Bytes($recoverableItemsSizeBytes) GiB) `
    -TotalItemCount ($activeItemCount + $recoverableItemsCount) `
    -TotalItemSize (Format-Bytes($activeItemsSizeBytes + $recoverableItemsSizeBytes) GiB) `
    -EffectiveItemSize (Format-Bytes(($activeItemsSizeBytes + $recoverableItemsSizeBytes) * $global:ExchangeMultiplicationFactor) GiB)
    
    if($ExoMode -ne 'PublicFolder')
    {
        # Generate statistics output for archive mailboxes
        $exchangeOutput += Add-Stats -Category " " `
        -ObjectType "$ExoMode Archive Mailboxes" `
        -ObjectCount $allArchiveMailboxesCount `
        -ItemCount $archiveItemsCount `
        -ItemSize (Format-Bytes($archiveItemsSizeBytes) GiB) `
        -RecoverableItemCount $archiveRecoverableItemsCount `
        -RecoverableItemSize (Format-Bytes($archiveRecoverableItemsSizeBytes) GiB) `
        -TotalItemCount ($archiveItemsCount + $archiveRecoverableItemsCount) `
        -TotalItemSize (Format-Bytes($archiveItemsSizeBytes + $archiveRecoverableItemsSizeBytes) GiB) `
        -EffectiveItemSize (Format-Bytes(($archiveItemsSizeBytes + $archiveRecoverableItemsSizeBytes) * $global:ExchangeMultiplicationFactor) GiB)
    }

    # Updating the final Exchange Online output variables
    $global:exoTotalMailboxes += $allMailboxesCount
    $global:exoTotalArchiveMailboxes += $allArchiveMailboxesCount
    $global:exoTotalActiveMailboxItemCount += $activeItemCount
    $global:exoTotalActiveMailboxItemsSize += $activeItemsSizeBytes
    $global:exoTotalRecoverableItemCount += $recoverableItemsCount
    $global:exoTotalRecoverableItemsSize += $recoverableItemsSizeBytes
    $global:exoTotalArchiveMailboxItemCount += $archiveItemsCount
    $global:exoTotalArchiveMailboxItemsSize += $archiveItemsSizeBytes
    $global:exoTotalArchiveRecoverableItemCount += $archiveRecoverableItemsCount
    $global:exoTotalArchiveRecoverableItemsSize += $archiveRecoverableItemsSizeBytes

    # Updating the final Exchange Online output for default only options
    if($ExoMode -ne "SoftDeleted")
    {
        $global:exoDefaultMailboxes += $allMailboxesCount
        $global:exoDefaultActiveMailboxItemCount += $activeItemCount
        $global:exoDefaultActiveMailboxItemsSize += $activeItemsSizeBytes
    }

    return $exchangeOutput
}

#----------------------------------------------------------------------------------------------------
# Function to get overall statistics data for Exchange Online.
#----------------------------------------------------------------------------------------------------

function Get-ExchangeStats
{
    Param 
    ( 
        [Parameter(Mandatory=$false)][string]$ADGroupToProcess
    )

    $exoOutput = @()

    if([string]::IsNullOrEmpty($ADGroupToProcess))
    {
        $exoOutput += Start-ExchangeThreadJobs -ExoMode User
    
        if($global:ProcessSoftDeletedMailboxes)
        {
            $exoOutput += Start-ExchangeThreadJobs -ExoMode SoftDeleted
        }
    
        $exoOutput += Start-ExchangeThreadJobs -ExoMode Group

        $exoOutput += Start-ExchangeThreadJobs -ExoMode PublicFolder
    }
    else 
    {
        $exoOutput += Start-ExchangeThreadJobs -ExoMode ADGroupUsers -ADGroupToProcess $ADGroupToProcess       
    }
    # Get Exchange Online storage usage report for 180 days
    $exchangeGrowthStats = Get-GrowthRate -Type Exchange
    
    # Generate total ouput for default only options
    $exoOutput += Add-Stats -Category "Exchange Online" `
    -ObjectType "Total Mailboxes with Default Options Only" `
    -ObjectCount $global:exoDefaultMailboxes `
    -ItemCount $global:exoDefaultActiveMailboxItemCount `
    -ItemSize $(Format-Bytes($global:exoDefaultActiveMailboxItemsSize) GiB) `
    -TotalItemCount $global:exoDefaultActiveMailboxItemCount `
    -TotalItemSize $(Format-Bytes($global:exoDefaultActiveMailboxItemsSize) GiB) `
    -EffectiveItemSize $(Format-Bytes($global:exoDefaultActiveMailboxItemsSize * $global:ExchangeMultiplicationFactor) GiB)
    
    # Generate total output for all options
    $exoOutput += Add-Stats -Category "Exchange Online" `
    -ObjectType "Total Mailboxes with All Option Enabled" `
    -ObjectCount $($global:exoTotalMailboxes + $global:exoTotalArchiveMailboxes) `
    -ItemCount $($global:exoTotalActiveMailboxItemCount + $global:exoTotalArchiveMailboxItemCount) `
    -ItemSize $(Format-Bytes($global:exoTotalActiveMailboxItemsSize + $global:exoTotalArchiveMailboxItemsSize) GiB) `
    -RecoverableItemCount $($global:exoTotalRecoverableItemCount + $global:exoTotalArchiveRecoverableItemCount) `
    -RecoverableItemSize $(Format-Bytes($global:exoTotalRecoverableItemsSize + $global:exoTotalArchiveRecoverableItemsSize) GiB) `
    -TotalItemCount $($global:exoTotalActiveMailboxItemCount + $global:exoTotalArchiveMailboxItemCount + $global:exoTotalRecoverableItemCount + $global:exoTotalArchiveRecoverableItemCount) `
    -TotalItemSize $(Format-Bytes($global:exoTotalActiveMailboxItemsSize + $global:exoTotalArchiveMailboxItemsSize + $global:exoTotalRecoverableItemsSize + $global:exoTotalArchiveRecoverableItemsSize) GiB) `
    -EffectiveItemSize $(Format-Bytes(($global:exoTotalActiveMailboxItemsSize + $global:exoTotalArchiveMailboxItemsSize + $global:exoTotalRecoverableItemsSize + $global:exoTotalArchiveRecoverableItemsSize) * $global:ExchangeMultiplicationFactor) GiB) `
    -DataGrowth $exchangeGrowthStats[0]  `
    -GrowthRate $exchangeGrowthStats[1]
    
    Add-Log "Completed statistics collection for Exchange Online." 
   
    Disconnect-ExchangeOnline -Confirm:$false
    
    return $exoOutput
}

#----------------------------------------------------------------------------------------------------
# Function to get statistics data for SharePoint Online
#----------------------------------------------------------------------------------------------------

function Get-SharePointStats
{
    Param 
    ( 
        [Parameter(Mandatory=$true)][string]$AdminUrl,
        [Parameter(Mandatory=$true)][ValidateSet("SharePoint","Team")] [string]$SPOMode
    ) 

    Connect-SharePoint -AdminUrl $global:SPOAdminUrl

    # Define outout variables
    $sharePointOutput = @()
    $allSharePointTotalSize = 0
    $allSharePointSites = $null

    # Get list of all sharepoint sites
    Add-Log "Getting list of all active $SPOMode sites.."
    if($SPOMode -eq 'SharePoint')
    {
        $allSharePointSites = Get-PnPTenantSite | Where-Object {$_.Template -notin ('RedirectSite#0','group#0','teamchannel#0','teamchannel#1','sitepagepublishing#0')}
    }
    elseif($SPOMode -eq 'Team') 
    {
        $allSharePointSites = Get-PnPTenantSite | Where-Object {$_.Template -in ('group#0','teamchannel#0','teamchannel#1','sitepagepublishing#0')}
    }
    
    $allSharePointSitesCount = $allSharePointSites.Count
    $currentSite = 0
    $percentComplete = 0

    foreach ($sharePointSite in $allSharePointSites)
    {
        Write-Progress -Activity "Calculating size of all $SPOMode sites." -Status "$percentComplete% Complete:" -PercentComplete $percentComplete 

        $currentSite++
        $percentComplete = [int](($currentSite / $allSharePointSitesCount) * 100)

        $siteUrl = $sharePointSite.Url
        
        # Get storage statistics for SharePoint site data
        $allSharePointTotalSize += $sharePointSite.StorageUsage
        
        # Log the individual site size in GiB
        $stTotalSize = [Math]::Round($sharePointSite.StorageUsage/1024,3)
        Add-Log "Site: $siteUrl Size: $stTotalSize GiB." -Level LogOnly
    }
    Write-Progress -Activity "Calculating size of all $SPOMode sites." -Status "Ready" -Completed

    # Get SharePoint Online data. 
    # SharePoint Storage Usage property output is in MBs.
    $sharePointActualSize = [Math]::Round($allSharePointTotalSize/[math]::Pow(1024,1),3)
    
    Add-Log "Completed statistics collection for $SPOMode sites. Total Sites: $allSharePointSitesCount, Total Items: --, Total Size: $sharePointActualSize GiB."

    # For total output calculation is in bytes so converting the output into bytes
    $global:spoSiteCount += $allSharePointSitesCount
    $global:spoTotalSize += $($allSharePointTotalSize * 1024 * 1024)
    
    $sharePointOutput += Add-Stats -Category " " -ObjectType "$SPOMode Sites" -ObjectCount $allSharePointSitesCount -TotalItemSize $sharePointActualSize -EffectiveItemSize $sharePointActualSize
    
    if($SPOMode -eq 'Team')
    {
        # Get SharePoint Online storage usage report for 180 days
        $sharepointGrowthStats = Get-GrowthRate -Type SharePoint
        $sharePointOutput += Add-Stats -Category "SharePoint Online" -ObjectType "Total Sites" -ObjectCount $global:spoSiteCount -TotalItemSize $(Format-Bytes($global:spoTotalSize) GiB) -EffectiveItemSize $(Format-Bytes($global:spoTotalSize) GiB) -DataGrowth $sharepointGrowthStats[0] -GrowthRate $sharepointGrowthStats[1]
    }

    return $sharePointOutput
}

#----------------------------------------------------------------------------------------------------
# Function to get statistics data for OneDrive
#----------------------------------------------------------------------------------------------------

function Get-OneDriveStats
{
    Param 
    (
        [Parameter(Mandatory=$true)][string]$AdminUrl, 
        [Parameter(Mandatory=$false)][string]$ADGroupToProcess
    ) 

    Connect-SharePoint -AdminUrl $global:SPOAdminUrl

    # Define outout variables
    $oneDriveOutput = @()
    $allOneDriveSitesTotalSize = 0

    # Get list of all OneDrive sites
    Add-Log "Getting list of all OneDrive active sites.."

    $tenantOneDriveSites = Get-PnPTenantSite -IncludeOneDriveSites -Filter {Url -like '-my.sharepoint.com/personal/'} | Where-Object {$_.Template -notin ('RedirectSite#0')}
        
    if([string]::IsNullOrEmpty($ADGroupToProcess))
    {
        $allOneDriveSites = $tenantOneDriveSites
    }
    else 
    {
        try 
        {  
            $adGroupUsers = @()
            
            $allADGroups = $ADGroupToProcess.Split(',')

            foreach($group in $allADGroups)
            {
                $adgroup = Get-MgGroup -Filter "DisplayName eq '$group'" -ErrorAction Stop
                $adGroupUsers += Get-MgGroupMember -GroupId $adgroup.Id -All -ErrorAction Stop
            }

            # Combined list of users from multiple groups might have duplicate users. So Getting unique entries only.
            $uniqueAdGroupUsers = $adGroupUsers | Sort-Object -Property Id -Unique
        }
        catch
        {
            $exception = $_.Exception.Message
            Add-Log "Failed to get the users from group $group." -Level Error
            Add-log "Exception: $exception" -Level LogOnly
        }

        $allOneDriveSites = @()

        foreach ($adGroupUser in $uniqueAdGroupUsers)
        {
            try 
            {
                $allOneDriveSites += $tenantOneDriveSites | Where-Object {$_.Owner -eq $adGroupUser.AdditionalProperties["userPrincipalName"]}
            }
            catch 
            {
                $exception = $_.Exception.Message
                Add-Log "Failed to get the OneDrive properties for user $($adGroupUser.AdditionalProperties["displayName"])." -Level Error
                Add-log "Exception: $exception" -Level LogOnly
            }
        }
    }
    $allOneDriveSitesCount = $allOneDriveSites.Count
    $currentSite = 0
    $percentComplete = 0

    foreach ($oneDriveSite in $allOneDriveSites)
    {
        Write-Progress -Activity "Calculating size of all OneDrive sites." -Status "$percentComplete% Complete:" -PercentComplete $percentComplete 

        $currentSite++
        $percentComplete = [int](($currentSite / $allOneDriveSitesCount) * 100)

        $siteUrl = $oneDriveSite.Url

        # Get storage statistics for OneDrive site data
        $allOneDriveSitesTotalSize += $oneDriveSite.StorageUsage             

        # Log the individual OneDrive size in GiB
        $odTotalSize = [Math]::Round($oneDriveSite.StorageUsage/1024,3)
        Add-Log "Site: $siteUrl Size: $odTotalSize GiB." -Level LogOnly
    }
    Write-Progress -Activity "Calculating size of all OneDrive sites." -Status "Ready" -Completed
    
    # Get OneDrive data 
    $oneDriveActualSize = [Math]::Round($allOneDriveSitesTotalSize/[math]::Pow(1024,1),3)

    # For total output calculation is in bytes so converting the output into bytes
    $global:oneDriveSiteCount += $allOneDriveSitesCount
    $global:oneDriveTotalSize += $($allOneDriveSitesTotalSize * 1024 * 1024)

    # Get OneDrive storage usage report for 180 days
    $oneDriveGrowthStats = Get-GrowthRate -Type OneDrive

    $oneDriveOutput += Add-Stats -Category "OneDrive for Business" -ObjectType "Personal Sites" -ObjectCount $allOneDriveSitesCount -TotalItemSize $oneDriveActualSize -EffectiveItemSize $oneDriveActualSize -DataGrowth $oneDriveGrowthStats[0] -GrowthRate $oneDriveGrowthStats[1]
    Add-Log "Completed statistics collection for OneDrive. Total Sites: $allOneDriveSitesCount, Total Items: --, Total Size: $oneDriveActualSize TiB." 

    return $oneDriveOutput
}

#----------------------------------------------------------------------------------------------------
# Function to get statistics data for Teams Chat
#----------------------------------------------------------------------------------------------------

function Get-TeamsChatStats
{
    $teamsOutput = @()

    $totalUsersMessages = 0
    $totalUsers = 0
    $totalTeamsMessages = 0
    
    $userStatsFile = "${PSScriptRoot}\TeamsStatsUserActivity-$global:date.csv"

    Connect-MicrosoftGraph

    Add-Log "Getting teams chat statistics of last 180 days."

    # Get team user activity report
    try 
    {
        Get-MgReportTeamUserActivityUserDetail -Period D180 -OutFile $userStatsFile -PassThru -ErrorAction stop
        Add-Log "Successfully downloaded the Teams user activity report."
    }
    catch 
    {
        $exception = $_.Exception.Message
        Add-Log "Error occurred while getting the Teams statistics. Exception: $exception" -Level Error
        return     
    }
    
    # Read downloaded csv files
    $userCsv = Import-Csv $userStatsFile
    
    # If csv file doesnt contain any data then return null
    if($userCsv.Count -eq 0)
    {
        Add-Log "Report does not contain data for user activity." -Level Error
        return
    }

    # Count number of messages for each user in the report
    foreach($uStat in $userCsv)
    {
        $totalUsersMessages += $uStat.("Private Chat Message Count")
        Add-Log "User $($uStat.("User Id")) has sent $($uStat.("Private Chat Message Count")) messages in private chat in last 180 days." -Level LogOnly
        $totalTeamsMessages += $uStat.("Team Chat Message Count")
        Add-Log "User $($uStat.("User Id")) has sent $($uStat.("Team Chat Message Count")) messages in teams channels in last 180 days." -Level LogOnly
        $totalUsers++
    }

    $unitUserMessages = [Math]::Round(($totalUsersMessages * $global:TeamsChatMultiplicationFactor),0)
    $unitTeamMessages = [Math]::Round(($totalTeamsMessages * $global:TeamsChatMultiplicationFactor),0)
    $unitTotalMessages = [Math]::Round(($unitUserMessages + $unitTeamMessages),0)
    $unitTotalMessagesNextYear = [Math]::Round(($unitTotalMessages * 3.03),0) # Current 180 days + next 365 days predicted data (180+365)/180

    $teamsOutput += Add-Stats -Category " " -ObjectType "Estimated Metered Units for User Chats" -ObjectCount $unitUserMessages
    $teamsOutput += Add-Stats -Category " " -ObjectType "Estimated Metered Units for Teams Channel Conversations" -ObjectCount $unitTeamMessages
    $teamsOutput += Add-Stats -Category " " -ObjectType "Total Estimated Metered Units (Last 180 Days)" -ObjectCount $unitTotalMessages
    $teamsOutput += Add-Stats -Category "Teams Chat" -ObjectType "Total Estimated Metered Units (Last 180 Days + Next 1 Year)" -ObjectCount $unitTotalMessagesNextYear

    Add-Log "Completed statistics collection for Teams. Total estimated metered units for last 180 days : $unitTotalMessages" 
    Add-Log "Total estimated metered units for last 180 days and next 1 year : $unitTotalMessagesNextYear" 

    Remove-Item -Path $userStatsFile -Force -Confirm:$false

    return $teamsOutput
}

#----------------------------------------------------------------------------------------------------
# Get sizing for M365 workloads
#----------------------------------------------------------------------------------------------------

function Get-M365Sizing
{
    # Change this value to session timeout value (in hours) for your M365 tenant. 
    $global:M365SessionTimeOut = 96 # hours

    # This is a multiplicator factor for Exchange Online data
    # Multiplication factor of 1.347 for items with binary attachments. Analysis indicates 0.85 of Exchange size is taken up by items with attachments
    $global:ExchangeMultiplicationFactor = (0.15 * 1) + (0.85 * 1.347)

    # This is multiplication factor for Teams Chat Messages
    # Multiplication factor of 1.4 (additional 40%) for all messages captured using teams export api.
    $global:TeamsChatMultiplicationFactor = 1.4

    # Inputs for workloads
    $global:ProcessExchange = $true
    $global:ProcessSharePoint = $true
    $global:ProcessOneDrive = $true
    $global:ProcessTeamsChat = $true

    # Inputs for Exchange Online
    $global:ProcessArchiveMailboxes = $true
    $global:ProcessRecoverableItems = $true
    $global:ProcessSoftDeletedMailboxes = $true
    $global:LimitScopeToADGroup = $false
    $global:ADGroup = $null

    # Authentication Inputs
    $global:AuthMode = 'UserLogin'
    $global:AppName = "M365-$global:date"
    $global:AppThumbprint = $null
    $global:AppID = $null
    $global:TenantId = $null
    $global:AzOrg = $null

    # Output for SharePoint Online
    $global:SPOAdminUrl = $null
    $global:spoSiteCount = 0
    $global:spoItemCount = 0
    $global:spoTotalSize = 0

    # Output for OneDrive for Business
    $global:oneDriveSiteCount = 0
    $global:oneDriveItemCount = 0
    $global:oneDriveTotalSize = 0

    # Output for Exchange Online
    $global:exoTotalMailboxes = 0
    $global:exoTotalArchiveMailboxes = 0
    $global:exoTotalActiveMailboxItemCount = 0
    $global:exoTotalActiveMailboxItemsSize = 0
    $global:exoTotalRecoverableItemCount = 0
    $global:exoTotalRecoverableItemsSize = 0
    $global:exoTotalArchiveMailboxItemCount = 0
    $global:exoTotalArchiveMailboxItemsSize = 0
    $global:exoTotalArchiveRecoverableItemCount = 0
    $global:exoTotalArchiveRecoverableItemsSize = 0
    $global:exoDefaultMailboxes = 0
    $global:exoDefaultActiveMailboxItemCount = 0
    $global:exoDefaultActiveMailboxItemsSize = 0

    # Check which M365 workloads to process for statistics collection
    Select-M365Options

    Add-Log "`n#--------------------------------------------------------------------------------------------------------------------------------------#" -Level Warn
    Add-Log "| This script uses two modes of authentication:                                                                                        |" -Level Warn
    Add-Log "| 1. Login with admin user credentials (UserLogin)                                                                                     |" -Level Warn
    Add-Log "|      . This mode will require user having permission to connect to Exchange and SharePoint admin                                     |" -Level Warn
    Add-Log "| 2. Azure AD app-only authentication  (Application)                                                                                   |" -Level Warn
    Add-Log "|      . An Azure AD application will be created with following permission. This app should be given admin consent manually.           |" -Level Warn
    Add-Log "|          Permission required for reading storage usage reports                                                                       |" -Level Warn
    Add-Log "|          . Microsoft Graph > Reports.Read.All - Application                                                                          |" -Level Warn
    Add-Log "|          . Microsoft Graph > User.Read.All - Application                                                                             |" -Level Warn
    Add-Log "|          Permission required for reading site storage usage                                                                          |" -Level Warn
    Add-Log "|          . Sharepoint > Sites.FullControl.All - Application                                                                          |" -Level Warn
    Add-Log "|          . Sharepoint > User.Read.All - Application                                                                                  |" -Level Warn
    Add-Log "|          Permission required for reading mailbox usage                                                                               |" -Level Warn
    Add-Log "|          . Office 365 Exchange Online > Exchange.ManageAsApp - Application                                                           |" -Level Warn
    Add-Log "#--------------------------------------------------------------------------------------------------------------------------------------#" -Level Warn

    # Take user input for authentication mode
    Select-M365AuthMode

    # Check if requried powershell module for M365 are available
    Test-Environment

    # Use custom app created by user
    if($global:AuthMode -eq 'CustomApp')
    {
        $global:TenantId = Read-Host "Enter the organization Tenant ID"
        $global:AzOrg = Read-Host "Enter the organization name (primary domain)"
        $global:AppID = Read-Host "Enter the application ID of the custom app"
        $global:AppThumbprint = Read-Host "Enter the Thumbprint of a certificate uploaded to the custom app"
    }    
    
    # Connect Microsoft graph
    Connect-MicrosoftGraph
    Add-Log "Organization `"$($global:AzOrg)`" with tenant id `"$($global:TenantId)`" has been selected for sizing."

    # Get User Credentials
    if($global:AuthMode -eq 'UserLogin')
    {
        Add-Log "Enter the admin credentials to connect to M365 resources." -Level Action
        $global:Credentials = Get-Credential -Message "Admin Credentials for M365 Tenant" -ErrorAction Stop
    }

    # Register new app in AAD and take admin grant for this app. 
    if($global:AuthMode -eq 'Application')
    {
        New-AppReg
    }
   
    # Process workloads
    if($global:ProcessExchange)
    {
        $global:output += Get-ExchangeStats -ADGroupToProcess $global:ADGroup
        $global:output += Add-Stats -Category " "
    }
    if($global:ProcessSharePoint)
    {
        $global:output += Get-SharePointStats -AdminUrl $global:SPOAdminUrl -SPOMode SharePoint
        $global:output += Get-SharePointStats -AdminUrl $global:SPOAdminUrl -SPOMode Team
        $global:output += Add-Stats -Category " "
    }
    if($global:ProcessOneDrive)
    {
        $global:output += Get-OneDriveStats -AdminUrl $global:SPOAdminUrl -ADGroupToProcess $global:ADGroup
        $global:output += Add-Stats -Category " "
    }
    if($global:ProcessTeamsChat)
    {
        $global:output += Get-TeamsChatStats
        $global:output += Add-Stats -Category " "
    }

    $totalWorkloadSize = Format-Bytes($global:exoTotalActiveMailboxItemsSize + $global:exoTotalArchiveMailboxItemsSize + $global:exoTotalRecoverableItemsSize + $global:exoTotalArchiveRecoverableItemsSize + $global:spoTotalSize + $global:oneDriveTotalSize) GiB
    $totalWorkloadEffectiveSize = Format-Bytes((($global:exoTotalActiveMailboxItemsSize + $global:exoTotalArchiveMailboxItemsSize + $global:exoTotalRecoverableItemsSize + $global:exoTotalArchiveRecoverableItemsSize) * $global:ExchangeMultiplicationFactor) + $global:spoTotalSize + $global:oneDriveTotalSize) GiB 

    $licUsers = Get-M365LicensedUsers
    $global:output += Add-Stats -Category "M365 Tenant" -ObjectType "Licensed Users" -ObjectCount $licUsers
    $global:output += Add-Stats -Category "M365 Tenant" -ObjectType "Total Size" -TotalItemSize $totalWorkloadSize -EffectiveItemSize $totalWorkloadEffectiveSize
    $global:output += Add-Stats -Category " "
    $global:output += Add-Stats -Category " "

    $global:output += Add-Stats -Category "Authentication mode used for this report is: $($global:AuthMode)"

    # Disconnect all services connected before..
    Add-Log "Disconnecting the services.."
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null

    if($null -ne $global:AppID)
    {
        Add-Log "The application $($global:AppName) with client id $($global:AppID) is no longer needed. It can be safely deleted." -Level Action
    }
}

#----------------------------------------------------------------------------------------------------
# Get authorization code for Google services
#----------------------------------------------------------------------------------------------------

function Get-GoogleAuthCode
{
    Add-Log "`nAuthorization windows will open, login with Google service account to generate the authorization code." -Level Action

    $global:Scopes = "https://www.googleapis.com/auth/admin.reports.usage.readonly","https://www.googleapis.com/auth/drive.readonly"

    # Start interactive one time authorization to generate access token
    Start-Process "https://accounts.google.com/o/oauth2/v2/auth?client_id=$($global:GoogleClientId)&scope=$([string]::Join("%20", $($global:Scopes)))&access_type=offline&response_type=code&redirect_uri=urn:ietf:wg:oauth:2.0:oob"

    $global:GoogleAuthCode = Read-Host "`nPlease enter the authorization code"

    if([String]::IsNullOrEmpty($global:GoogleAuthCode))
    {
        Add-Log "Authorization code is not valid. Exiting.." -Level Error
        exit
    }
}

#----------------------------------------------------------------------------------------------------
# Get access token to call Google services API
#----------------------------------------------------------------------------------------------------

function Get-GoogleAccessToken
{
    try 
    {
        $tokenResponse = $null

        if(($global:GoogleTokenExpiryTime -lt [System.DateTime]::Now) -and (-not [String]::IsNullOrEmpty($global:GoogleAccessToken)))
        {
            Add-Log "Current access token has expired. Getting new access token using refresh token." -Level LogOnly
            $tokenResponse = Invoke-WebRequest https://www.googleapis.com/oauth2/v4/token -ContentType application/x-www-form-urlencoded -Method POST -Body "client_id=$($global:GoogleClientId)&client_secret=$($global:GoogleClientSecret)&redirect_uri=urn:ietf:wg:oauth:2.0:oob&refresh_token=$($global:GoogleRefreshToken)&grant_type=refresh_token" -ErrorAction Stop
            $global:GoogleAccessToken = ($tokenResponse.Content | ConvertFrom-Json).$access_token
            $global:GoogleTokenExpiryTime = [System.DateTime]::Now.AddSeconds(3000);
        }
        elseif([String]::IsNullOrEmpty($global:GoogleAccessToken))
        {
            Add-Log "Generating a new access token." -Level LogOnly
            $tokenResponse = Invoke-WebRequest https://www.googleapis.com/oauth2/v4/token -ContentType application/x-www-form-urlencoded -Method POST -Body "client_id=$($global:GoogleClientId)&client_secret=$($global:GoogleClientSecret)&redirect_uri=urn:ietf:wg:oauth:2.0:oob&code=$($global:GoogleAuthCode)&grant_type=authorization_code" -ErrorAction Stop
            $global:GoogleRefreshToken = ($tokenResponse.Content | ConvertFrom-Json).refresh_token
            $global:GoogleAccessToken = ($tokenResponse.Content | ConvertFrom-Json).access_token
            $global:GoogleTokenExpiryTime = [System.DateTime]::Now.AddSeconds(3000);
        }
        else
        {
            Add-Log "Current access token is valid. Using same access token." -Level LogOnly
        }
    }
    catch 
    {
        $exception = $_.Exception.Message
        Add-Log "Failed to get access token for Google services api. Exiting.." -Level Error
        Add-log "Exception: $exception" -Level LogOnly
        exit
    }
}

#----------------------------------------------------------------------------------------------------
# Call Google api
#----------------------------------------------------------------------------------------------------

function Invoke-GoogleApi
{
    Param
    (
        [Parameter(Mandatory=$true)][string]$RequestUrl
    )

    try 
    {
        Add-Log "Calling Google api. Request Url : $RequestUrl" -Level LogOnly
        
        Get-GoogleAccessToken

        $headers = @{ "Authorization" = "Bearer $($global:GoogleAccessToken)" }

        $response = Invoke-WebRequest -Method Get -Uri $RequestUrl -Headers $headers -ErrorAction Stop

        if($null -ne $response)
        {
            Add-Log "Google api call is successful." -Level LogOnly
        }

        return $response.Content
    }
    catch
    {
        $exception = $_.Exception.Message
        Add-Log "Google api call failed with exception: $exception." -Level LogOnly
        return $null
    }
}

#----------------------------------------------------------------------------------------------------
# Get Google sizing data
#----------------------------------------------------------------------------------------------------

function Get-GoogleSizing
{
    # This is a multiplicator factor for Gmail data
    # Multiplication factor of 3 for gmail items. This covers the expansion of the attachments for base64 encoding and cover for an average use of labels.
    $global:GmailMultiplicationFactor = 3

    $global:GoogleAuthCode = $null
    $global:GoogleAccessToken = $null
    $global:GoogleRefreshToken = $null
    $global:GoogleTokenExpiryTime = [System.DateTime]::Now

    # Application for connecting to Google services. 
    $global:GoogleClientId = Read-Host "`nEnter the Google OAuth 2.0 Client Id"
    
    $global:GoogleClientSecret = Read-Host "`nEnter the Client Secret"
    
    # Get Google authorization code for current session to call the Google Apis.
    Get-GoogleAuthCode -ClientId $global:GoogleClientId -Scopes $global:Scopes

    # Get customer usage report from Google services api
    $reportDate = [System.DateTime]::Now
    $retries = 0
    $isReportReady = $false
    $parameters = "accounts:total_quota_in_mb,accounts:customer_used_quota_in_mb,accounts:drive_used_quota_in_mb,accounts:gmail_used_quota_in_mb,accounts:shared_drive_used_quota_in_mb,accounts:num_users,gmail:num_email_accounts"

    # Get Google customer report
    do
    {
        $reportDateString = Get-Date -Date $reportDate -Format "yyyy-MM-dd"
        $responseContent = Invoke-GoogleApi -RequestUrl "https://admin.googleapis.com/admin/reports/v1/usage/dates/$($reportDateString)?parameters=$parameters" -ErrorAction SilentlyContinue
        
        # If report for current date is not available then check for previous date.
        if($null -eq $responseContent)
        {
            Add-Log "Google usage report is not available for date $reportDate. Trying to get report on previous date." -Level Warn
            $reportDate = $reportDate.AddDays(-1)
            $retries++
            $isReportReady = $false
        }
        else 
        {
            Add-Log "Google usage report is available for date $reportDate."
            $responseObj = $responseContent | ConvertFrom-Json
            $isReportReady = $true
            
            # Get report for date 180 days before current date.
            $reportDateOld = $reportDate.AddDays(-180)
            $reportDateStringOld = Get-Date -Date $reportDateOld -Format "yyyy-MM-dd"
            $responseContentOld = Invoke-GoogleApi -RequestUrl "https://admin.googleapis.com/admin/reports/v1/usage/dates/$($reportDateStringOld)?parameters=$parameters" -ErrorAction SilentlyContinue
            $responseObjOld = $responseContentOld | ConvertFrom-Json
        }
    } 
    while (($retries -le 10) -and (-not $isReportReady))

    if(-not $isReportReady)
    {
        Add-Log "Failed to get Google workspace usage report using api."
        return
    }

    # Get shared drive count 
    $sharedDriveResponseContent = Invoke-GoogleApi -RequestUrl "https://www.googleapis.com/drive/v3/drives?useDomainAdminAccess=true"
    $sharedDriveObj = $sharedDriveResponseContent | ConvertFrom-Json
    $sharedDrivesList = $sharedDriveObj.drives
    while(-not [String]::IsNullOrEmpty($sharedDriveObj.nextPageToken)) 
    {
        $sharedDriveResponseContent = Invoke-GoogleApi -RequestUrl "https://www.googleapis.com/drive/v3/drives?useDomainAdminAccess=true&pageToken=$($sharedDriveObj.nextPageToken)"
        $sharedDriveObj = $sharedDriveResponseContent | ConvertFrom-Json
        $sharedDrivesList += $sharedDriveObj.drives
        $sharedDriveResponseContent = $null
    }

    # Get Google workload usage statistics
    $totalDriveUsage = [Math]::Round((($responseObj.usageReports[0].parameters | Where-Object {$_.name -eq 'accounts:drive_used_quota_in_mb'}).intValue)/1024,3)
    $totalGmailUsage = [Math]::Round((($responseObj.usageReports[0].parameters | Where-Object {$_.name -eq 'accounts:gmail_used_quota_in_mb'}).intValue)/1024,3)
    $totalSharedDriveUsage = [Math]::Round((($responseObj.usageReports[0].parameters | Where-Object {$_.name -eq 'accounts:shared_drive_used_quota_in_mb'}).intValue)/1024,3)
    $totalGoogleUsage = $totalDriveUsage + $totalGmailUsage + $totalSharedDriveUsage
    $totalEffectiveGoogleUsage = $totalDriveUsage + $($totalGmailUsage * $global:GmailMultiplicationFactor) + $totalSharedDriveUsage

    # Get Google workload user counts
    $totalDriveUsers = ($responseObj.usageReports[0].parameters | Where-Object {$_.name -eq 'accounts:num_users'}).intValue
    $totalGmailUsers = ($responseObj.usageReports[0].parameters | Where-Object {$_.name -eq 'gmail:num_email_accounts'}).intValue
    $totalSharedDrives = $sharedDrivesList.Count

    # Get Google customer total usage
    $totalCustomerQuota  = [Math]::Round((($responseObj.usageReports[0].parameters | Where-Object {$_.name -eq 'accounts:total_quota_in_mb'}).intValue)/1024,3)
    $totalCustUsedQuota  = [Math]::Round((($responseObj.usageReports[0].parameters | Where-Object {$_.name -eq 'accounts:customer_used_quota_in_mb'}).intValue)/1024,3)

    # Get growth rate for 180 days
    $sizeToday = ($responseObj.usageReports[0].parameters | Where-Object {$_.name -eq 'accounts:customer_used_quota_in_mb'}).intValue
    $size180daysBefore = ($responseObjOld.usageReports[0].parameters | Where-Object {$_.name -eq 'accounts:customer_used_quota_in_mb'}).intValue
    $googleGrowthSize = [Math]::Round(($sizeToday-$size180daysBefore)/1024,3)
    $googleGrowthRate = [Math]::Round(((($sizeToday-$size180daysBefore)*100)/$size180daysBefore),2)

    # Generating output for Google workspace
    $global:output += Add-Stats -Category " " -ObjectType "Drive" -ObjectCount $totalDriveUsers -TotalItemSize $totalDriveUsage -EffectiveItemSize $totalDriveUsage
    $global:output += Add-Stats -Category " " -ObjectType "Gmail" -ObjectCount $totalGmailUsers -TotalItemSize $totalGmailUsage -EffectiveItemSize $($totalGmailUsage * $global:GmailMultiplicationFactor)
    $global:output += Add-Stats -Category " " -ObjectType "Shared Drive" -ObjectCount $totalSharedDrives -TotalItemSize $totalSharedDriveUsage -EffectiveItemSize $totalSharedDriveUsage
    $global:output += Add-Stats -Category "Google WorkSpace (Report Date: $reportDateString)" -ObjectType "Total Customer Usage" -ObjectCount $totalDriveUsers -TotalItemSize $totalGoogleUsage -EffectiveItemSize $totalEffectiveGoogleUsage -DataGrowth $googleGrowthSize -GrowthRate "$googleGrowthRate`%"
    $global:output += Add-Stats -Category " "
    $global:output += Add-Stats -Category " "
}

#--------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Main Program
#--------------------------------------------------------------------------------------------------------------------------------------------------------------------

$global:date = [System.DateTime]::Now.ToString("yyyyMMdd-hhmmss")

$ScriptName = ([io.fileinfo]$MyInvocation.MyCommand.ScriptBlock.File).BaseName
$LogName = $ScriptName+"-"+$global:date+".log"
$global:LogFilePath = "${PSScriptRoot}\$LogName"	

# Check if later version of script is available for download.
Test-ScriptVersion

# Print the header containing name of the program and version number.
Write-ScriptInfo

# Start time of the script
$scriptStartTime = [System.DateTime]::Now

# Script output variable
$global:output = @()

# Common Variables
$global:ProcessM365 = $false
$global:ProcessGoogle = $false
$global:ProcessBox = $false

# Check which workloads to process for statistics collection
Select-SizingOption

# Process M365 workloads
if($global:ProcessM365)
{
    Get-M365Sizing
}

# Process Google workloads
if($global:ProcessGoogle)
{
    Get-GoogleSizing
}

# End time of the script
$scriptEndTime = [System.DateTime]::Now
$scriptExecutionTime = New-TimeSpan -Start $scriptStartTime -End $scriptEndTime

# Important notes added at the bottom of the report in CSV file.
$global:output += Add-Stats -Category "Time taken to run this script is $(($scriptExecutionTime.Days * 24) + $scriptExecutionTime.Hours) hours $($scriptExecutionTime.Minutes) minutes."

# Generate report and export in CSV file
Add-Log "Generating the report at location ${PSScriptRoot}\ASP-Sizing-$global:date.csv."
$global:output | Export-CSV "${PSScriptRoot}\ASP-Sizing-$global:date.csv" -NoTypeInformation -Append

Add-Log "For detailed stats and errors please refer logs created at location $global:LogFilePath."

Add-Log "Completed!"
