# Define the modules to be installed
$modules = @(
    "Microsoft.Graph",
    "ExchangeOnlineManagement",
    "SharePointPnPPowerShellOnline",
    "ThreadJob"
)

# Array to track installed modules
$installedModulesList = @()

# Install the latest versions of the required modules
foreach ($module in $modules) {
    # Check if the module is already installed
    $installedModule = Get-InstalledModule -Name $module -ErrorAction SilentlyContinue
    if ($null -eq $installedModule) {
        # Install the module if not installed
        Install-Module -Name $module -Force -Scope CurrentUser
        Write-Host "$module installed."
        # Add to the installed modules list
        $installedModulesList += $module
    } else {
        Write-Host "$module already installed with version $($installedModule.Version)."
    }
}

# Check for the existence of PnP.PowerShell
$pnpModule = Get-InstalledModule -Name "PnP.PowerShell" -ErrorAction SilentlyContinue
if ($null -ne $pnpModule) {
    Write-Host "Warning: PnP.PowerShell must not exist. It is currently installed."
} else {
    Write-Host "PnP.PowerShell is not installed as required."
}

# Display only the installed modules
if ($installedModulesList.Count -gt 0) {
    Write-Host "The following modules were installed:"
    $installedModulesList | ForEach-Object { Write-Host $_ }
} else {
    Write-Host "No new modules were installed."
}
