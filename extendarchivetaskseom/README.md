# Extend Archive Task End-of-Month Retention

A PowerShell script to **extend retention for archived snapshots** on Cohesity clusters to the end of an extended month, based on a specific snapshot date or last snapshot of the previous/current month.

---

## Table of Contents

- [Overview](#overview)  
- [Features](#features)  
- [Prerequisites](#prerequisites)  
- [Parameters](#parameters)  
- [Examples](#examples)  
- [Debugging](#debugging)  
- [Output](#output)  

---

## Overview

This script calculates a new snapshot expiration date based on:  

- A provided snapshot date (`-snapshotDate`)  
- The last snapshot of the previous or current month (`-lastSnapshotOfPreviousMonth`, `-lastSnapshotOfCurrentMonth`)  
- A date range (`-StartDate` and `-EndDate`)  

Retention can be extended either **by months** (`-extendMonths`) or manually overridden with **days to keep** (`-daysToKeep`).  

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory.

```powershell
# End Download Commands
$repoURL = 'https://raw.githubusercontent.com/CohesityDMaaS/Automation/main/extendarchivetaskseom'
# Download the main script
(Invoke-WebRequest -Uri "$repoURL/extendarchivetaskseom.ps1" -UseBasicParsing).Content | Out-File "extendarchivetaskseom.ps1"
# Download the dependency (cohesity-api.ps1) in the same folder
(Invoke-WebRequest -Uri "$repoURL/cohesity-api.ps1" -UseBasicParsing).Content | Out-File "cohesity-api.ps1"
# End Download Commands
```

## Components

* [Extendarchivetaskseom.ps1](https://github.com/CohesityDMaaS/Automation/blob/main/extendarchivetaskseom/extendarchivetaskseom.ps1): the main powershell script
* [cohesity-api.ps1](https://raw.githubusercontent.com/CohesityDMaaS/Automation/main/extendarchivetaskseom/cohesity-api.ps1): the Cohesity REST API helper module

Place both files in a folder together, and then we can run the script.


Supports:  

- Dry-run mode (`-DryRun`)  
- Commit changes to Cohesity (`-commit`)  
- Debug logging (`-DebugLog`)  
- Optional CSV export (`-SummaryCsv`)  

---

## Features

- Calculates extended snapshot retention automatically.  
- Filters by snapshot date, job names, or policy names.  
- Handles cross-month snapshot retention correctly.  
- Provides detailed console and debug output.  
- Optional CSV summary of adjustments for reporting.  

---

## Prerequisites

- PowerShell 5.1 or later  
- Access to a Cohesity cluster  
- `cohesity-api.ps1` module in the same folder  
- User account with permissions to view and modify archival snapshots  

---

## Parameters

| Parameter | Description | Required | Type |
|-----------|-------------|----------|------|
| `-vip` | Cohesity cluster IP or hostname | Yes | String |
| `-username` | Admin username | Yes | String |
| `-password` | Admin password (optional, will prompt if not supplied) | No | String |
| `-domain` | Domain for authentication (default: `local`) | No | String |
| `-extendMonths` | Number of months to extend retention | No (required if `-daysToKeep` not used) | Int |
| `-daysToKeep` | Manually specify retention in days | No (required if `-extendMonths` not used) | Int |
| `-snapshotDate` | Filter snapshots by a specific date | No | DateTime |
| `-StartDate` | Start date for date range filter | No | DateTime |
| `-EndDate` | End date for date range filter | No | DateTime |
| `-includeSnapshotDay` | Include the snapshot day in retention calculation | No | Switch |
| `-jobNames` | Array of job names to include | No | Array |
| `-policyNames` | Array of policy names to include | No | Array |
| `-target` | Filter archival target vault name | No | String |
| `-allowReduction` | Allow reducing retention if new expiry is earlier | No | Switch |
| `-commit` | Commit changes to Cohesity | No | Switch |
| `-DryRun` | Show changes without committing | No | Switch |
| `-SummaryCsv` | Path to export summary CSV | No | String |
| `-lastSnapshotOfPreviousMonth` | Use last snapshot of previous month as reference | No | Switch |
| `-lastSnapshotOfCurrentMonth` | Use last snapshot of current month as reference | No | Switch |
| `-DebugLog` | Enable debug logging for troubleshooting | No | Switch |

---

## Examples

### Dry-run extending snapshots by 1 month for a specific date

```powershell
.\extendarchivetaskseom.ps1 -vip 10.100.0.11 -username admin -snapshotDate 2025-10-28 -extendMonths 1 -DryRun
