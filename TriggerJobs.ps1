param(
    [Parameter(ParameterSetName="Standard")][String]$username,
    [Parameter(ParameterSetName="Standard")][String]$password,
    [Parameter(ParameterSetName="Interactive")][Switch]$Interactive
)
<#
    CONFIG

    Register PnP and get the clientid by doing:
     Register-PnPEntraIDApp -ApplicationName "PnP PowerShell App Registration" -Tenant [tenant].onmicrosoft.com -Interactive
#>
$clientid = '62b0270a-153a-4fb2-b8b9-602fb1131362'

$database = "otcs_extraction_050724"
$mongocs  = "mongodb://HOST:27017/$($database)"

<#
    START
#>
switch ($PSCmdlet.ParameterSetName)
{
    'Standard'
    {
        <# Run in SharePointOnline Management Shell. Don't load PnP #>
        try
        {
            Import-Module Mdbc -ErrorAction Stop
        }
        catch
        {
            $env:PSModulePath = $env:PSModulePath+";.\Modules"
            Import-Module Mdbc -ErrorAction Stop
        }
    }
    'Interactive'
    {
        <# Run in PowerShell 7. Load PnP #>
        try
        {
            Import-Module PnP.PowerShell -ErrorAction Stop
            Import-Module Mdbc -ErrorAction Stop
        }
        catch
        {
            $env:PSModulePath = $env:PSModulePath+";.\Modules"
            Import-Module PnP.PowerShell -ErrorAction Stop
            Import-Module Mdbc -ErrorAction Stop
        }

    }
}

Connect-Mdbc -connectionstring $mongocs -databasename $database -collectionname 'documents' -ErrorAction Stop

$global:context = $null

Get-MdbcData -Filter @{"migration.migrate"=$True; "source.contentType.systemName"="SPOPackage"; "source.properties.azure.migrationJobId"=$null} |
ForEach {
    try
    {
        $package = $_

        $siteurl  = $package.source.properties.spo.webUrl
        $dataUri  = $package.source.properties.azure.azureContainerSourceUri
        $metaUri  = $package.source.properties.azure.azureContainerManifestUri
        $queueUri = $package.source.properties.azure.azureQueueReportUri
        $enckey   = [Convert]::FromBase64String($package.source.properties.azure.encryptionKey)

        if($null -eq $context -or $context.url.toLower() -ne $siteurl.toLower())
        {
            Write-Host "Connecting to $siteurl"
            switch ($PSCmdlet.ParameterSetName)
            {
                'Standard'
                {
                    $credentials = new-object System.Management.Automation.PSCredential($username, (ConvertTo-SecureString -AsPlainText -Force -String $password))

                    $context = New-Object Microsoft.SharePoint.Client.ClientContext($siteurl)    
                    $context.Credentials = New-Object Microsoft.SharePoint.Client.SharePointOnlineCredentials($username, (ConvertTo-SecureString -AsPlainText -Force -String $password))
                    #$pnpconnection = Connect-PnPOnline -Credentials $credentials -Url $siteurl -ReturnConnection -WarningAction Ignore -ClientId $clientid -ErrorAction Stop
                    break
                }
                'Interactive'
                {
                    $pnpconnection = Connect-PnPOnline -Interactive -Url $siteurl -ReturnConnection -WarningAction Ignore -ClientId $clientid -ErrorAction Stop
                    $context = $pnpconnection.context
                    break
                }
                Default
                {
                    Write-Host "Invalid Arguments" -ForegroundColor Red
                    exit
                }
            }

            while($True)
            {
                try
                {
                    $context.load($context.web)
                    $context.executequery()
                    break
                }
                catch
                {
                    if($_.Exception.Message.contains("The underlying connection was closed"))
                    {
                        Write-Host $_.Exception.Message -ForegroundColor Red
                        Write-Host "Retrying..."
                        Start-Sleep -Seconds 5
                    }
                    else
                    {
                        throw
                    }
                }
            }
        }

        $private:enc = new-object microsoft.sharepoint.client.encryptionoption
        $enc.aes256cbckey = $enckey
        $jobid = $context.site.CreateMigrationJobEncrypted($context.web.id, $dataUri, $metaUri, $queueUri, $enc)
        $context.executequery()
        Write-Host "Job Invoked $($jobid.value.toString())"
        Update-MdbcData -Filter @{'_id'=$package._id} -Update @{'$set'=@{'source.properties.azure.migrationJobId'=$jobid.value.toString(); 'migration.failed'=$False}}
    }
    catch
    {
        Write-Host $_.Exception.Message -ForegroundColor Red
        Update-MdbcData -Filter @{'_id'=$package._id} -Update @{'$set'=@{'migration.failed'=$True; 'migration.failedMessage'=$_.Exception.Message}}
    }
}