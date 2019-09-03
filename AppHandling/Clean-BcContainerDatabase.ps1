﻿<# 
 .Synopsis
  Cleans the Database in a BC Container
 .Description
  This function will remove existing base app from the database in a container, leaving the container without app
  You will have to publish a new base app before Business Central is useful
 .Parameter containerName
  Name of the container in which you want to clean the database
 .Parameter saveData
  Include the saveData switch if you want to save data while uninstalling apps
 .Parameter onlySaveBaseAppData
  Include the onlySaveBaseAppData switch if you want to only save data in the base application and not in other apps
 .Parameter doNotUnpublish
  Include the doNotUnpublish switch if you do not want to unpublish apps (only 15.x containers or later)
 .Example
  Clean-BcContainerDatabase -containerName test
#>
function Clean-BcContainerDatabase {
    Param (
        [string] $containerName = "navserver",
        [switch] $saveData,
        [Switch] $onlySaveBaseAppData,
        [switch] $doNotUnpublish
    )

    $platform = Get-NavContainerPlatformversion -containerOrImageName $containerName
    if ("$platform" -eq "") {
        $platform = (Get-NavContainerNavVersion -containerOrImageName $containerName).Split('-')[0]
    }
    [System.Version]$platformversion = $platform

    if ($platformversion.Major -lt 14) {
        throw "Container $containerName does not support the function Clean-NavContainerDatabase"
    }

    $myFolder = Join-Path $ExtensionsFolder "$containerName\my"

    if (!(Test-Path "$myFolder\license.flf")) {
        throw "Container must be started with a developer license in order to publish a new application"
    }

    $customconfig = Get-NavContainerServerConfiguration -ContainerName $containerName

    $installedApps = Get-NavContainerAppInfo -containerName $containerName -tenantSpecificProperties -sort DependenciesLast | Where-Object { $_.Name -ne "System Application" }
    $installedApps | % {
        $app = $_
        Invoke-ScriptInBCContainer -containerName $containerName -scriptblock { Param($app, $SaveData, $onlySaveBaseAppData)
            if ($app.IsInstalled) {
                Write-Host "Uninstalling $($app.Name)"
                $app | Uninstall-NavApp -Force -doNotSaveData:(!$SaveData -or ($Name -ne "BaseApp" -and $Name -ne "Base Application" -and $onlySaveBaseAppData))
            }
        } -argumentList $app, $SaveData, $onlySaveBaseAppData
    }

    if ($platformversion.Major -eq 14) {
        Invoke-ScriptInNavContainer -containerName $containerName -scriptblock { Param ( $customConfig )
            
            if ($customConfig.databaseInstance) {
                $databaseServerInstance = "$($customConfig.databaseServer)\$($customConfig.databaseInstance)"
            }
            else {
                $databaseServerInstance = $customConfig.databaseServer
            }
    
            Write-Host "Removing C/AL Application Objects"
            Delete-NAVApplicationObject -DatabaseName $customConfig.databaseName -DatabaseServer $databaseServerInstance -Filter 'ID=1..1999999999' -SynchronizeSchemaChanges Force -Confirm:$false

        } -argumentList $customconfig
    }
    else {
        if (!$doNotUnpublish) {
            $installedApps | % {
                $app = $_
                Invoke-ScriptInBCContainer -containerName $containerName -scriptblock { Param($app)
                    if ($app.IsPublished) {
                        Write-Host "Unpublishing $($app.Name)"
                        $app | UnPublish-NavApp
                    }
                } -argumentList $app
            }
        }
    }
}
Export-ModuleMember -Function Clean-BcContainerDatabase
