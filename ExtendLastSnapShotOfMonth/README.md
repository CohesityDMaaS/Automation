# Extend the last day of the month Snapshots to the end of X amount of months

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is, and the author accepts no liability for damages resulting from its use.

This script will extend the retention of the last-day-of-month snapshots to X months. Processed snapshots will be logged to extendLog_$timestamp.txt.

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory.

```powershell
# End Download Commands
$repoURL = 'https://raw.githubusercontent.com/CohesityDMaaS/Automation/main/ExtendLastSnapShotOfMonth'
# Download the main script
(Invoke-WebRequest -Uri "$repoURL/ExtendLastSnapShotOfMonth.ps1").Content | Out-File "ExtendLastSnapShotOfMonth.ps1"
# Download the dependency (cohesity-api.ps1) in the same folder
(Invoke-WebRequest -Uri "$repoURL/cohesity-api.ps1").Content | Out-File "cohesity-api.ps1"
# End Download Commands
```

## Components

* [ExtendLastSnapShotOfMonth.ps1](https://raw.githubusercontent.com/CohesityDMaaS/Automation/main/ExtendLastSnapShotOfMonth/ExtendLastSnapShotOfMonth.ps1): the main powershell script
* [cohesity-api.ps1](https://raw.githubusercontent.com/CohesityDMaaS/Automation/main/ExtendLastSnapShotOfMonth/cohesity-api.ps1): the Cohesity REST API helper module

Place both files in a folder together, and then we can run the script.

First, you can just run the script WITH the -DryRun switch to see what would be extended.

```powershell
./ExtendLastSnapShotOfMonth.ps1 -vip mycluster -username myuser -domain mydomain.net -DryRun
```
Then, if you're happy with the list of snapshots to be processed, run the script again and replace -dryrun with -commit. This will execute the extension tasks.

```powershell
./ExtendLastSnapShotOfMonth.ps1 -vip mycluster -username myuser -domain mydomain.net -commit
```

## Parameters

* **-vip: (Required)** Cohesity Cluster to connect to
* **-username: (Required)** Cohesity username
* **-dryrun: (Required)** performs a Dry Run of extensions
* **-commit: (Required)** perform extensions
* **-extendmonths: (Required)** number of months to extend
* -domain: (optional) Active Directory domain of user (defaults to local)
* -includeSnapshotDay: (optional) includes the snapshot day (To correct being 1 day off)
* -includecrossmonth: (optional) includes snaphsots that start before the last day of the month but end on that day
* -includereversecrossmonth: (optional) includes snapshots that start on the last day of the month but end after it
* -logpath: (optional) custom log file path. If not provided, one is auto-generated ( extendLog_YYYY-MM-DD_HHmm.txt ) 
  
## Job Selection Parameters (default is all local jobs)

* -jobName: (optional) one or more job names (comma separated)
* -jobList: (optional) text file of job names (one per line)
* -policyName: (optional) one or more policy names (comma separated)
* -policyList: (optional) text file of policy names (one per line)
* -includeReplicas: (optional) extend snapshots replicated to this cluster (default is local jobs only)


## Note

If `-policyName` or `-policyList` are used, then only local jobs can be processed.
