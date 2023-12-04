# Deploy AWS SaaS Connectors using PowerShell

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This powershell script deploys AWS SaaS Connector EC2 Instances to Registered CCS AWS Sources.

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory

```powershell
# Download Commands
$scriptName = 'Deploy_CCS_AWSsaasConns'
$repoURL = 'https://raw.githubusercontent.com/CohesityDMaaS/Automation/main'
(Invoke-WebRequest -Uri "$repoUrl/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
(Invoke-WebRequest -Uri "$repoUrl/$scriptName/README.md").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "README.md"
# End Download Commands
```

## Components

* deployAWSsaasConns.ps1: the main powershell script

Run the main script like so:

```powershell
./deployAWSsaasConns.ps1 -apiKey #### -CCSregionId us-east-1 -AWSregionId us-east-1 -AWSid #### -subnetId subnet-#### -securityGroupId sg-#### -vpcId vpc-#### -saasNo 2 -AWStag "label=value", "label=value" -connAdd
```

## Parameters

* -apiKey : apiKey generated in CCS UI
* -CCSregionId: CCS region where AWS is Registered
* -AWSid: AWS Account ID
* -AWSregionId: AWS region where SaaS Connector EC2 Instance will be deployed
* -subnetId: AWS Subnet Identifier
* -securityGroupId: AWS Network Security Group
* -vpcId: AWS VPC Id
* -saasNo: (optional) Number of AWS SaaS Connector EC2 Instances to create
* -AWStag: (optional) AWS SaaS Connector EC2 Instance Tags (comma separated). example: "label=value", "label2=value2"
* -AWStags: (optional) text file of AWS SaaS Connector EC2 Instance Tags (one per line)
* -connAdd: switch to append to command line when adding addition CCS AWS SaaS Connectors to an already existing SaaS Connection Group

## Authenticating to CCS

CCS uses an API key for authentication. To acquire an API key:

* log onto CCS
* click Settings -> access management -> API Keys
* click Add API Key
* enter a name for your key
* click Save

Immediately copy the API key (you only have one chance to copy the key. Once you leave the screen, you can not access it again).
