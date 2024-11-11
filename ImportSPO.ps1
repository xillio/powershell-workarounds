function Trigger-Jobs
{
    param(
        [Parameter(Mandatory=$True, ParameterSetName="Standard")][String]$Username,
        [Parameter(Mandatory=$True, ParameterSetName="Standard")][String]$Password,
        [Parameter(Mandatory=$True, ParameterSetName="Interactive")][Switch]$Interactive,
        [Parameter(Mandatory=$True, ParameterSetName="Certificate")][String]$ClientId,
        [Parameter(Mandatory=$True, ParameterSetName="Certificate")][String]$Thumbprint,
        [Parameter(Mandatory=$True, ParameterSetName="Certificate")][String]$Tenant,
        [String]$MongoHost='127.0.0.1',
        [String]$MongoPort=27017,
        [Parameter(Mandatory=$True)][String]$MongoDatabase,
        [String]$MongoCollection='documents'
    )

    switch ($PSCmdlet.ParameterSetName)
    {
        'Standard'
        {
            <# Run in SharePointOnline Management Shell. Don't load PnP #>
            Import-Module Mdbc -ErrorAction Stop
            break
        }
        {$_ -eq 'Interactive' -or $_ -eq 'Certificate'}
        {
            <# Run in PowerShell 7. Load PnP #>
            Import-Module PnP.PowerShell -ErrorAction Stop
            Import-Module Mdbc -ErrorAction Stop
            break
        }
        Default
        {
            Write-Host "Invalid Arguments" -ForegroundColor Red
            exit
        }
    }

    $mongocs  = "mongodb://$($MongoHost):$($MongoPort)/$($MongoDatabase)"
    Connect-Mdbc -connectionstring $mongocs -databasename $MongoDatabase -collectionname $MongoCollection -ErrorAction Stop

    $global:context = $null

    Get-MdbcData -Filter @{"migration.migrate"=$True; "source.contentType.systemName"="SPOPackage"; "source.properties.azure.migrationJobId"=$null} -ErrorAction Stop |
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
                        $context = New-Object Microsoft.SharePoint.Client.ClientContext($siteurl)    
                        $context.Credentials = New-Object Microsoft.SharePoint.Client.SharePointOnlineCredentials($username, (ConvertTo-SecureString -AsPlainText -Force -String $password))
                        break
                    }
                    'Interactive'
                    {
                        $pnpconnection = Connect-PnPOnline -Interactive -Url $siteurl -ReturnConnection -WarningAction Ignore -ClientId $clientid -ErrorAction Stop
                        $context = $pnpconnection.context
                        break
                    }
                    'Certificate'
                    {
                        $pnpconnection = Connect-PnPOnline -Url $siteurl -ReturnConnection -WarningAction Ignore -ClientId $ClientId -Thumbprint $Thumbprint -Tenant $Tenant -ErrorAction Stop
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
            throw
        }
    }
}