# Cohesity Replication Run End of Month Retention Script

A PowerShell script to manage and execute Cohesity protection group backups with customizable replication retention settings that are stored at the End of the Month.

## Overview

This script automates the execution of Cohesity protection groups (backup jobs) with advanced control over replication retention periods. It supports dry-run mode for testing, comprehensive logging, and flexible job selection through individual job names or batch processing via file input.

## Features

- ✅ **Flexible Authentication**: Supports local, Helios, API key, and Entra ID authentication
- ✅ **Selective Job Execution**: Run single jobs or multiple jobs from a list
- ✅ **Custom Retention Control**: Set replication retention to end-of-month plus configurable months
- ✅ **Dry-Run Mode**: Preview actions without executing jobs
- ✅ **Comprehensive Logging**: Optional transcript logging with custom path support
- ✅ **Progress Monitoring**: Real-time job status and progress tracking
- ✅ **Error Handling**: Robust retry logic and timeout management

## Prerequisites

- **PowerShell**: Version 5.1 or higher
- **Cohesity API Module**: `cohesity-api.ps1` (must be in the same directory)
- **Permissions**: Appropriate Cohesity cluster access rights
- **Network**: Connectivity to Cohesity cluster or Helios

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory.

```powershell
# End Download Commands
$repoURL = 'https://raw.githubusercontent.com/CohesityDMaaS/Automation/main/BackupNowReplica'
# Download the main script
(Invoke-WebRequest -Uri "$repoURL/BackupNowReplica.ps1" -UseBasicParsing).Content | Out-File "BackupNowReplica.ps1"
# Download the dependency (cohesity-api.ps1) in the same folder
(Invoke-WebRequest -Uri "$repoURL/cohesity-api.ps1" -UseBasicParsing).Content | Out-File "cohesity-api.ps1"
# End Download Commands
```

## Usage

### Basic Syntax

```powershell
.\BackupNowReplica.ps1 -vip <cluster> -username <user> [-Commit|-DryRun] [options]
```

### Authentication Examples

**Local Authentication:**
```powershell
.\BackupNowReplica.ps1 -vip mycluster.company.com -username admin -domain local -Commit
```

**Helios Authentication:**
```powershell
.\BackupNowReplica.ps1 -username admin@company.com -useApiKey -mcm -clusterName "Production-Cluster" -Commit
```

**Entra ID Authentication:**
```powershell
.\BackupNowReplica.ps1 -vip mycluster.company.com -username user@domain.com -EntraId -Commit
```

### Dry-Run Mode

Preview what would happen without executing jobs:
```powershell
.\BackupNowReplica.ps1 -vip mycluster.company.com -username admin -JobName "Critical-DB" -DryRun
```

### Job Selection Examples

**Run a single job:**
```powershell
.\BackupNowReplica.ps1 -vip mycluster.company.com -username admin -JobName "SQL-Backup-Daily" -Commit
```

**Run multiple jobs from a file:**
```powershell
.\BackupNowReplica.ps1 -vip mycluster.company.com -username admin -JobList "C:\jobs\backup-list.txt" -Commit
```

**Process all active jobs:**
```powershell
.\BackupNowReplica.ps1 -vip mycluster.company.com -username admin -Commit
```
### Custom Retention Period

Set replication retention to end-of-month plus 6 months:
```powershell
.\BackupNowReplica.ps1 -vip mycluster.company.com -username admin -keepReplicaForMonths 6 -Commit
```

### Enable Logging

```powershell
.\BackupNowReplica.ps1 -vip mycluster.company.com -username admin -WriteLog -Commit
```

**With custom log path:**
```powershell
.\BackupNowReplica.ps1 -vip mycluster.company.com -username admin -WriteLog -LogPath "C:\Logs\cohesity-backup.log" -Commit
```

## Parameters

### Authentication Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-vip` | String | `helios.cohesity.com` | Cohesity cluster hostname or IP |
| `-username` | String | `helios` | Username for authentication |
| `-password` | String | `$null` | Password (prompted if not provided) |
| `-domain` | String | `local` | Authentication domain |
| `-useApiKey` | Switch | - | Use API key authentication |
| `-mcm` | Switch | - | Connect to Helios/MCM |
| `-EntraId` | Switch | - | Use Entra ID authentication |
| `-clusterName` | String | `$null` | Specific cluster name (for Helios) |

### Job Selection Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-JobName` | String | - | Single job name to execute |
| `-JobList` | String | - | Path to text file with job names (one per line) |
| `-RunPausedJobs` | Switch | - | Allow processing paused jobs (otherwise skip) |
| `-UnpausePausedJobs` | Swtich | - | If Paused, Temporarily unpause to run (best-effort) |
| `-RePauseAfterRun` | Switch | - | If UnPaused, Re-Pause after run submission

### Behavior Control Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-DryRun` | Switch | - | Show actions without executing jobs |
| `-Commit` | Switch | - | Actually execute jobs |
| `-keepReplicaForMonths` | Int | `4` | Months to keep replica (to end-of-month) |

### Tuning Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-timeoutSec` | Int | `300` | API call timeout in seconds |
| `-statusRetries` | Int | `10` | Max status check retries |
| `-sleepTimeSecs` | Int | `60` | Sleep time between status checks |
| `-waitForNewRunMinutes` | Int | `50` | Max wait time for new run to appear |
| `-startWaitTime` | Int | `30` | Initial wait before checking for new run |
| `-retryWaitTime` | Int | `60` | Wait time between retries |
| `-noCache` | Switch | - | Disable API response caching |

### Logging Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-WriteLog` | Switch | - | Enable console output to file |
| `-LogPath` | String | Auto-generated | Custom log file path |

## Job List File Format

Create a text file with one job name per line:

```
SQL-Production-Daily
FileServer-Backup
VMware-Critical-VMs
Oracle-Database-Backup
```

## Retention Calculation

The script calculates retention based on the **end-of-month** for the specified number of months ahead:

- **Today**: 2025-12-10
- **keepReplicaForMonths**: 4
- **Target Date**: 2025-04-30 (end of month, 4 months from now)
- **Days to Keep**: Calculated days from today to target end-of-month minus 1 day buffer

## Output Examples

### Dry-Run Output
```
=== Processing: SQL-Production-Daily ===
Today:            2025-12-10
Target EOM:       2026-04-30
raw daysToEOM:    141

If a replication run starts today (2025-12-10), expiration (Target EOM) would be: 2026-04-30
  Target: DR-Cluster -> expiration (Target EOM): 2026-04-30

DryRun: NOT starting job SQL-Production-Daily. Use -Commit to actually run with these settings.
```

### Commit Output
```
=== Processing: SQL-Production-Daily ===
Started: SQL-Production-Daily
New run: 12345:67890:1234567890
50 percent complete
100 percent complete
Job finished with status: Succeeded
OK SQL-Production-Daily completed successfully
```

## Error Handling

The script handles common scenarios:

- **Job already running**: Gracefully skips and reports
- **Job not found**: Warns about missing jobs from list
- **Authentication failures**: Exits with error code 2
- **API timeouts**: Configurable retry logic
- **No active jobs**: Exits with error code 0

## Exit Codes

| Code | Description |
|------|-------------|
| `0` | Success or no jobs to process |
| `1` | Invalid parameters or job list file not found |
| `2` | Authentication failure |

## Best Practices

1. **Always test with `-DryRun` first** before using `-Commit`
2. **Enable logging** for production runs: `-WriteLog`
3. **Use job lists** for batch operations to maintain consistency
4. **Monitor retention periods** to ensure compliance with data retention policies
5. **Set appropriate timeouts** based on job complexity and network conditions

## Troubleshooting

### Jobs Not Starting
- Verify job names match exactly (case-sensitive)
- Check if jobs are already running
- Ensure proper authentication and permissions

### Timeout Issues
- Increase `-timeoutSec` for slow API responses
- Increase `-waitForNewRunMinutes` for slow job starts
- Check network connectivity to cluster

### Logging Issues
- Verify write permissions to log directory
- Ensure sufficient disk space
- Check if another process has locked the log file

## Security Considerations

- **Never hardcode passwords** in scripts
- Use **API keys** for automated workflows
- Store **job lists** in secure locations
- Review **log files** for sensitive information before sharing

## Contributing

Contributions are welcome! Please ensure:
- Code follows PowerShell best practices
- Parameters are documented
- Error handling is comprehensive
- Changes are backward compatible

## License

This script is provided as-is for use with Cohesity Data Protection platforms.

## Support

For issues related to:
- **Script functionality**: Open an issue in this repository
- **Cohesity API**: Contact Cohesity support
- **Cohesity platform**: Refer to official Cohesity documentation

---


