# Vault Run Status Report for Cohesity

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This script collects backup and vaulting (archive) run details for one or more Cohesity clusters and writes the results to CSV, Excel (xlsx), and HTML reports. For every protection group run, it captures the client/object name, local backup status and expiry, the external vault target, archive run status and expiry, data transferred, and average throughput. Results can be filtered by external target, archive run status, and a configurable lookback window, and are sorted by Run Date (descending) before being written out.

## Download the script

This script depends on the Cohesity PowerShell API function library, `cohesity-api.ps1`. Download both files into the same folder:

```powershell
# Download Commands
$scriptUrl = 'https://raw.githubusercontent.com/CohesityDMaaS/Automation/main/VaultRunStatus/vaultrunstatus.ps1'
(Invoke-WebRequest -UseBasicParsing -Uri $scriptUrl).content | Out-File -Force vaultrunstatus.ps1; (Get-Content vaultrunstatus.ps1) | Set-Content vaultrunstatus.ps1

$repoUrl = 'https://raw.githubusercontent.com/cohesity/community-automation-samples/main/powershell'
(Invoke-WebRequest -UseBasicParsing -Uri "$repoUrl/cohesity-api/cohesity-api.ps1").content | Out-File -Force cohesity-api.ps1; (Get-Content cohesity-api.ps1) | Set-Content cohesity-api.ps1
# End Download Commands
```

`vaultrunstatus.ps1` is hosted at [CohesityDMaaS/Automation](https://github.com/CohesityDMaaS/Automation/blob/main/VaultRunStatus/vaultrunstatus.ps1); `cohesity-api.ps1` must be placed in the same folder for authentication and API calls.

## Components

* **vaultrunstatus.ps1**: the main reporting script
* **cohesity-api.ps1**: the function library `vaultrunstatus.ps1` sources for authentication and API calls (see above)

Optional Excel export requires the `ImportExcel` PowerShell module:

```powershell
Install-Module -Name ImportExcel
```

## Authentication

`vaultrunstatus.ps1` accepts the same authentication parameters as `apiauth` in `cohesity-api.ps1`:

* -vip: (optional) endpoint to connect to (cluster, MCM, or Helios - defaults to helios.cohesity.com)
* -username: (optional) username to connect with
* -domain: (optional) Active Directory domain name of the user (defaults to local)
* -tenant: (optional) tenant to impersonate
* -password: (optional) hard code the password (not recommended) - the password will not be stored
* -useApiKey: (optional) use an API key for authentication (switch)
* -mcm: (optional) authenticate through Helios/MCM (switch)
* -mfaCode: (optional) TOTP MFA code
* -emailMfaCode: (optional) send an emailed MFA code (switch)
* -noPrompt: (optional) do not prompt for a password (switch)

When run against Helios (the default), the script will process every cluster connected to your Helios tenant unless `-clusterName` is specified.

## Parameters

* -clusterName: (optional) name of a single cluster to report on. If omitted while connected through Helios, every connected cluster is processed
* -numRuns: (optional) maximum number of runs to retrieve per protection group (default: 1000)
* -duration: (optional) how far back to pull runs from, e.g. `24h`, `2d`, `3d`, `1w`, `1m` for hours/days/weeks/months (default: `1d`)
* -unit: (optional) unit for Physical/Logical Transferred columns - `MiB` or `GiB` (default: `MiB`)
* -ExternalTarget: (optional) only report vaulting runs whose external target matches this name, checked against both `ownershipContext` and `targetName` (default: blank - includes every external target)
* -ArchiveRunStatus: (optional) only report runs with these Archive Run Status value(s): `Successful`, `Running`, `Failed`, `Canceled`. Accepts multiple values (default: blank - includes every status)

## Output

For each cluster processed, the script writes three reports to the current folder, named with the cluster name and today's date:

* `vaultInventory-<clusterName>-<yyyy-MM-dd>.csv`
* `vaultInventory-<clusterName>-<yyyy-MM-dd>.xlsx`
* `vaultInventory-<clusterName>-<yyyy-MM-dd>.html`

Each report includes the following columns:

* Job Name
* Backup Run Status
* client Name
* Object Type
* Run Date
* Backup Expiry Date
* External Target
* Archive Run Status
* Archive Expiry Date
* Physical Transferred (MiB/GiB)
* Logical Transferred (MiB/GiB)
* Average Throughput (Mbps)
* Vaulting Process Duration
* Failure Reason

If a filter (`-ExternalTarget` or `-ArchiveRunStatus`) matches nothing for a cluster, the script prints every distinct target/status combination it actually saw for that cluster, to help identify the correct filter value.

## Examples

Report on every FortKnox vaulting run, across all Helios-connected clusters, from the last 24 hours:

```powershell
.\vaultrunstatus.ps1 -vip helios.cohesity.com -username myuser -domain mydomain.net -ExternalTarget FortKnox
```

Report on a single cluster, going back one week, including every external target:

```powershell
.\vaultrunstatus.ps1 -vip mycluster -username myuser -domain mydomain.net -clusterName mycluster -duration 1w
```

Report only failed or canceled archive runs over the last month:

```powershell
.\vaultrunstatus.ps1 -vip helios.cohesity.com -username myuser -domain mydomain.net -duration 1m -ArchiveRunStatus Failed,Canceled
```

Report using GiB units for data transferred:

```powershell
.\vaultrunstatus.ps1 -vip helios.cohesity.com -username myuser -domain mydomain.net -unit GiB
```
