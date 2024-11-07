Import-Module PnP.PowerShell
Import-Module Mdbc

$mongocs = 'mongodb://localhost:27017/spo_extract_ps'
Connect-Mdbc -connectionstring $mongocs -databasename 'spo_extract_ps' -collectionname 'documents'

$username = 'USERNAME'
$password = ConvertTo-SecureString 'PASSWORD' -AsPlainText -Force
$siteUrl  = 'https://'
$context  = $null

function Main-Routine
# Called at the bottom of this script
{
    try
    {
        Extract-Site -Url $siteurl -Username $username -Password $password
    }
    catch
    {
        Write-Host $_.Exception.Message -ForegroundColor Red
        throw
    }
}


function Extract-Users
{
    param(
        [String]$Url,
        [String]$Username,
        [System.Security.SecureString]$Password,
        [String]$ClientId='62b0270a-153a-4fb2-b8b9-602fb1131362'
    )
    # Register-PnPEntraIDApp -ApplicationName “PnP PowerShell App Registration” -Tenant [tenant].onmicrosoft.com -Interactive
    $private:credentials = new-object System.Management.Automation.PSCredential($username, $password)
    $private:pnpconnection = Connect-PnPOnline -Credentials $credentials -Url $Url -ReturnConnection -WarningAction Ignore -ClientId $clientid -ErrorAction Stop

    $global:context = $pnpconnection.context
    $web = $context.web

    $context.load($web)
    $context.load($web.siteusers)
    $context.executequery()

    foreach($user in $web.siteusers)
    {
        $u = @{
            '_id'=$user.LoginName;
            'migration'=@{};
            'source'=@{
                'properties'=@{}
            }
        }
        Update-MdbcData -Filter @{'_id'=$u._id} -Update @{'$set'=$u} -Add
    }
}


function Extract-Site
{
    param(
        [String]$Url,
        [String]$Username,
        [System.Security.SecureString]$Password,
        [String]$ClientId='62b0270a-153a-4fb2-b8b9-602fb1131362'
    )
    # Register-PnPEntraIDApp -ApplicationName “PnP PowerShell App Registration” -Tenant [tenant].onmicrosoft.com -Interactive
    $private:credentials = new-object System.Management.Automation.PSCredential($username, $password)
    $private:pnpconnection = Connect-PnPOnline -Credentials $credentials -Url $Url -ReturnConnection -WarningAction Ignore -ClientId $clientid -ErrorAction Stop
    $tenantid = Get-PnPTenantId -Connection $pnpconnection

    $global:context = $pnpconnection.context
    $web = $context.web

    $context.load($web)
    $context.executequery()

    $site = Create-Xill4Site -Web $web
    Write-Host $site.source.properties.sharepointIds.siteUrl
    Update-MdbcData -Filter @{'_id'=$site._id} -Update @{'$set'=$site} -Add

    $context.load($web.lists)
    $context.executequery()

    foreach($list in $web.lists | where-object {$_.BaseTemplate -eq 101})
    {
        $context.load($list)
        $context.load($list.rootfolder)
        $context.executequery()

        $library = Create-Xill4DocumentLibrary -Xill4Site $site -List $list
        Write-Host "> $($library.source.properties.hierarchy)"
        Update-MdbcData -Filter @{'_id'=$library._id} -Update @{'$set'=$library} -Add

        $context.load($list.ContentTypes)
        $context.executequery()
        $list.ContentTypes | ForEach {$context.load($_)}
        $context.executequery()

        foreach($doctype in $list.ContentTypes)
        {
            $contenttype = Create-Xill4ContentType -Xill4List $library -ContentType $doctype

            Write-Host ">> $($contenttype.source.name.displayName)"
            Update-MdbcData -Filter @{'_id'=$contenttype._id} -Update @{'$set'=$contenttype} -Add
        }
    }
}

function Create-Xill4Site
{
    param(
        [Microsoft.SharePoint.Client.Web]$Web
    )

    [Void]($Web.Url -Match "(.*)/.*")
    $sitecollection = $sitecollection = $Matches[1]
    if($sitecollection.endsWith('/sites'))
    {
        $sitecollection = $sitecollection.substring(0, $sitecollection.length - '/sites'.length)
    }
    [Void]($Web.Url -Match "https://(.*?)/.*")
    $hostname = $Matches[1]

    [Void]($web.Path.Identity -Match '.*site:(.*):web:(.*)')
    $id0 = $Matches[1]
    $id1 = $Matches[2]
    $siteid = "$sitecollection,$id0,$id1"
    $underscoreid = "$sitecollection,$id0,$id1"

    [Void]($web.Url -Match ".*/(.*)")
    $name = $Matches[1]

    $site = @{
        '_id'=$underscoreid;
        'migration'=@{
            'migrate'=$True;
            'failed'=$False;
            'origin'='SharePoint Online';
            'flags'=@{}
        };
        'source'=@{
            'id'=$siteid;
            'parentids'=@();
            'hierarchies'=@($web.serverrelativeurl);
            'name'=@{'systemName'=$web.url; 'displayName'=$web.title};
            'contentType'=@{'displayName'='Site'; 'systemName'='Site'};
            'versionInfo'=@{'label'='1.0'; 'major'=1; 'minor'=0; 'seriesId'=$siteid; 'isCurrent'=$True};
            'states'=@{};
            'properties' = @{
                "createdDateTime"=$web.created;
                "id"=$siteid;
                "name"=$name;
                "webUrl"=$web.url;
                "displayName"=$web.title;
                "sharepointIds"=@{
                    "siteId"=$id0;
                    "siteUrl"=$web.url;
                    "tenantId"=$tenantid;
                    "webId"=$id1
                };
                "siteCollection"=@{
                    "hostname"=$hostname
                };
                "root"=@{};
                "contentType"="Site";
                "hierarchy"=$web.serverrelativeurl;
                "siteUnderscoreId"=$underscoreid        
            };
            'binaries'=@{};
            'acls'=@{};
            'auditLogs'=@{}
        };
    }

    return $site
}



function Create-Xill4DocumentLibrary
{
    param(
        [System.Collections.HashTable]$Xill4Site,
        [Microsoft.SharePoint.Client.List]$List
    )

    [Void]($list.rootfolder.serverrelativeurl -Match ".*/(.*)")
    $name = $Matches[1]

    $listid = "$($Xill4Site.source.properties.sharepointIds.siteId)/$($Xill4Site.source.properties.sharepointIds.webId)/$($list.Id)"

    $library = @{
        "_id"=$listid;
        "kind"="CONTAINER";
        "migration"=@{
            "migrate"=$true;
            "failed"=$false;
            "origin"="SharePoint Online";
            "flags"=@{
            }
        };
        "source"=@{
            "id"=$listid;
            "parentIds"=@($Xill4Site.source.id); 
            "hierarchies"=@($list.rootfolder.serverrelativeurl);
            "name"=@{
                "systemName"=$name;
                "displayName"=$list.Title
            };
            "description"="";
            "contentType"=@{
                "systemName"="documentLibrary";
                "displayName"="documentLibrary"
            };
            "versionInfo"=@{
                "label"="1.0";
                "major"=1;
                "minor"=0;
                "seriesId"=$list.Id;
                "isCurrent"=$true
            };
            "states"=@();
            "created"=@{
                "date"=$list.created;
                "principal"=@{
                    "systemName"="displayName(System Account)";
                    "displayName"="System Account"
                }
            };
            "lastModified"=@{
                "date"=$list.lastModified;
                "principal"=@{
                    "systemName"="cd5610a2-5abc-4ceb-805b-06fd28c71982";
                    "displayName"="Consultants Xillio"
                }
            };
            "owner"=@{
                "principal"=@{
                    "systemName"="1f72f014-6bfa-478a-b501-1100a8731a67";
                    "displayName"="onboarding_demo_wanga Owners"
                }
            };
            "properties"=@{
                "id"=$list.Id;
                "name"=$name;
                "webUrl"=$list.Url;
                "sharepointIds"=@{
                    "listId"=$list.Id;
                    "siteId"=$Xill4Site.source.properties.sharepointIds.siteId;
                    "siteUrl"=$Xill4Site.source.properties.sharepointIds.siteUrl;
                    "tenantId"=$tenandid;
                    "webId"=$Xill4Site.source.properties.sharepointIds.webId
                };
                "hierarchy"=$list.rootfolder.serverrelativeurl;
                "listName"=$name;
                "listUnderscoreId"=$listid;
                "listSourceId"=$listid;
                "listParentIds"="$($Xill4Site.source.properties.siteCollection.hostname),$($Xill4Site.source.properties.sharepointIds.siteId),$($Xill4Site.source.properties.sharepointIds.webId)";
                "listId"=$listid;
                "siteId"="$($Xill4Site.source.properties.siteCollection.hostname),$($Xill4Site.source.properties.sharepointIds.siteId),$($Xill4Site.source.properties.sharepointIds.webId)"
            };
            "binaries"=@();
            "acls"=@();
            "auditLogs"=@()
        }
    }
    return $library
}

function Create-Xill4ContentType
{
    param(
        [System.Collections.HashTable]$Xill4List,
        [Microsoft.SharePoint.Client.ContentType]$ContentType
    )

    $ct = @{
        "_id"=$ContentType.Id.tostring();
        "kind"="RECORD";
        "migration"=@{
            "migrate"=$true;
            "failed"=$false;
            "origin"="SharePoint Online"
        };
        "source"=@{
            "id"=$ContentType.Id.tostring();
            "parentIds"=@(
                $Xill4List.source.id
            );
            "hierarchies"=@();
            "name"=@{
                "systemName"=$ContentType.Id.toString();
                "displayName"=$ContentType.Name
            };
            "description"=$ContentType.description;
            "contentType"=@{
                "systemName"="ContentType";
                "displayName"="ContentType"
            };
            "versionInfo"=@{
                "label"="1.0";
                "minor"=0;
                "major"=1;
                "seriesId"=$ContentType.Id.toString();
                "isCurrent"=$true
            };
            "states"=@();
            "properties"=@{
                "id"=$ContentType.Id.tostring();
                "description"=$ContentType.description;
                "group"=$ContentType.Group;
                "hidden"=$false;
                "name"=$ContentType.Id.tostring();
                "parentId"=$Xill4LIst.source.id;
                "readOnly"=$false;
                "sealed"=$false;
                "columns"=@();
                "type"="ContentType";
                "displayName"=$ContentType.Name
            }
        }
    }

    $context.load($ContentType.Fields)
    $context.executequery()

    $ContentType.Fields |
    ForEach {
        $ct.source.properties.columns += @{'displayName'=$_.Title; 'name'=$_.InternalName; 'id'=$_.Id.tostring(); 'type'=$_.TypeAsString}
    }

    return $ct
}


Main-Routine