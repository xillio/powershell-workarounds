. .\ImportSPO.ps1

<#
    CONFIG
#>
$MongoHost       = '127.0.0.1'
$MongoPort       = 27017
$MongoDatabase   = 'NAME'
$mongoCollection = 'documents'

$ClientId   = 'CLIENTID'
$Thumbprint = 'THUMBPRINT'
$Tenant     = 'TENANT'

<#
    Make sure Mdbc and PnP.PowerShell are in the module path
#>
if(-not $env:PSModulePath.contains('.\Modules'))
{
    $env:PSModulePath = $env:PSModulePath+";.\Modules"
}

<#
    RUN
#>
Trigger-Jobs -MongoDatabase $MongoDatabase -MongoHost $MongoHost -MongoPort $MongoPort -MongoCollection $MongoCollection -ClientId $ClientId -Tenant $Tenant -Thumbprint $Thumbprint