This repository contains a few script that replicate functionality normally provided by a Xill4 flow but require different methods of authentication due to particular circumstances at clients.

# TriggerJobs.ps1
Script that triggers SharePoint Migratoin API jobs from the content-store.

## Prerequisites
### PowerShell
- Modules PnP.PowerShell and Mdbc. Either install via
  - Install-Module -Name PnP.PowerShell,
  - Install-Module -Name Mdbc.
  
  Or get the zips from this repository (see below)
- Powershell Version 7

### App Registration and Authentication
Pnp.PowerShell needs to be registered as an app in the AzureAD by:
- Register-PnPEntraIDApp -ApplicationName "PnP PowerShell App Registration" -Tenant [TENANT].onmicrosoft.com -Interactive

This requires a username/password/onetimepasscode to complete. This will generate a pfx file in the current directory

From the Azure Portal:
- The registered app needs to be given access to all relevant sitecollections (see https://www.sharepointdiary.com/2019/03/connect-pnponline-with-appid-and-appsecret.html)
- Note down the THUMBPRINT and the CLIENTID

On the local machine:
- The generated pfx file needs to be added to the local certificate store (dubbel click the file and follow instructions, leave the password blank when asked)

## Usage
- Download both scripts ImportPSO.ps1 and TriggerJobs.ps1.
- (Only needed if Mdbc and PnP.PowerShell are not installed via the Install-Module command) Download Mdbc.zip and PnP.PowerShell.zip and unzip them into a folder Modules right next to the above two files
- At the top of the script TriggerJobs.ps1 configure:
  - the Mongo database HOST, PORT, NAME, and COLLECTION
  - the CLIENTID and THUMBPRINT that were noted down from the Azure Portal
- In a PowerShell 7 window run TriggerJobs.ps1
