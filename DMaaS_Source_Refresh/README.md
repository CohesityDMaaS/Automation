# Protect DMaaS M365 Mailboxes using PowerShell

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This powershell script Refreshes DMaaS Sources.

## Components
* Ensure that the below two components are saved in the same directory:

* DMaaS_Source_Refresh.ps1: the main powershell script
* cohesity-api.ps1: the Cohesity REST API helper module

Place both files in a folder together and run the main script like so:

```powershell
./DMaaS_Source_Refresh.ps1 -region us-east-2 -sourceID 772,3306
```

## Parameters

* region: DMaaS region to use
* username: (optional) used for password storage only (default is 'DMaaS')
* sourceID: ID of registered M365 protection source

The ID of a Cohesity DMaaS Source can be found in the navigation bar of the internet browser after having clicked on the Source Name:
https://helios.cohesity.com/protections/sources/details/187694/objects?regionId=us-west-1&environment=kVMware

In the above address, the Source ID is: 187694

## Authenticating to DMaaS

DMaaS uses an API key for authentication. To acquire an API key:

* log onto DMaaS
* click Settings -> access management -> API Keys
* click Add API Key
* enter a name for your key
* click Save

Immediately copy the API key (you only have one chance to copy the key. Once you leave the screen, you can not access it again). When running a DMaaS compatible script for the first time, you will be prompted for a password. Enter the API key as the password.
