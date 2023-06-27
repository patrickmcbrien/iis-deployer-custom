param ($siteName,$nonInteractive,[Parameter(Mandatory=$true)][string[]]$Folders)


function Install-Pre-requisites([string] $nonInteractive)
{
    # check pre-requisites are installed.
    $requirements = "NET-Framework-45-Features", "Web-Net-Ext45", "Web-Asp-Net45", "Web-ISAPI-Ext", "Web-ISAPI-Filter"
    $nonInstalledRequirements = New-Object Collections.Generic.List[String]
    foreach ($item in $requirements)
    {
        $requirement = Get-WindowsFeature -Name $item | Where Installed
        if (-Not$requirement)
        {
            $nonInstalledRequirements.Add($item)
        }
        else
        {
            Write-Host ($item + " already installed")
        }
    }
    #  if one of the pre-requisites didn't install, ask ack from the user to install it.
    if ($nonInstalledRequirements)
    {
        if ($nonInteractive -ne "y" -or $nonInteractive -ne "Y")
        {
            write-host ("The following requirements are not installed`n" + $nonInstalledRequirements + "`n" + "Do you want to install them? [y/n]")
            $nonInteractive = Read-Host
        }
        if ($nonInteractive -eq "y" -or $nonInteractive -eq "Y")
        {
            foreach ($requirement in $nonInstalledRequirements)
            {
                Write-Host ("Installing " + $requirement + "`n")
                Install-WindowsFeature -Name $requirement
            }
        }
        else{
            Write-Host ("The following requirements cannot be installed.. exiting`n " + $nonInstalledRequirements)
            exit
        }
    }
}

function Create-Noname-Log
{
    Import-Module WebAdministration
    # Get the default IIS log file path
    $logPath = Get-WebConfigurationProperty -Filter /system.applicationHost/sites/siteDefaults/logfile -Name directory
    # Get the value for the directory property
    $logPath = $logPath.Value
    $logPath = $logPath.Replace("%SystemDrive%", "C:")
    $logPath = $logPath.Replace("\", "\\")
    $logPath = $logPath + "\\noname"
    # Create noname logs directory if needed
    if (!(Test-Path $logPath)) {
        New-Item -ItemType Directory -Path $logPath | Out-Null
    }
    # Set `Everyone` permissions
    $acl = Get-Acl $logPath
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone","FullControl","Allow")
    $acl.SetAccessRule($rule)
    Set-Acl $logPath $acl


    # Read the contents of the file
    $modulePath = Join-Path $PSScriptRoot 'NonameCustomModule.cs'
    $content = Get-Content -Path $modulePath
    # Replace the target string with the new value
    $newContent = $content -replace "{{ IIS_LOG_PATH }}", "$logPath"

    # Write the updated content back to the file
    Set-Content -Path $modulePath -Value $newContent
}

function Compile-Noname-Module
{
    $frameworkPath = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    $modulePath = Join-Path $PSScriptRoot 'NonameCustomModule.cs'
    $assemblyName = 'NonameApp.dll'

    & $frameworkPath /t:library /out:$assemblyName /o $modulePath /r:System.Web.dll
}

function Copy-Noname-Module-To-Site([string] $physicalPath, [array]$Folders)
{
    $binDir = Join-Path $physicalPath 'bin'
    if (!(Test-Path $binDir)) {
        New-Item -ItemType Directory -Path $binDir | Out-Null
    }
    $sourcePath = Join-Path $PSScriptRoot 'NonameApp.dll'
    $destinationPath = Join-Path $binDir 'NonameApp.dll'

    Copy-Item -Path $sourcePath -Destination $destinationPath -Force

    foreach ($folder in $Folders) {
    if (Test-Path -Path $folder -PathType Container) {
        $destinationPath = Join-Path -Path $folder -ChildPath (Split-Path -Path $sourcePath -Leaf)
        
        Write-Host "Copying '$sourcePath' to '$destinationPath'..."
        Copy-Item -Path $sourcePath -Destination $destinationPath -Force
    } else {
        Write-Host "Folder '$folder' does not exist or is not accessible."
    }
}

}

function Add-Noname-Module
{
    $filteredModules = Get-WebManagedModule | Where-Object Name -like "*Noname*"
    # Check if the web-managed-modules contains Noname module
    if ($filteredModules.Count -gt 0)
    {
        # The module is installed
        Write-Host ($filteredModules.Name + " module is already installed.`n")
    }
    else
    {
        # The module is not installed
        Write-Host "Noname module is not installed, so let's install it ...`n"
        New-WebManagedModule -Name "NonameCustomModule" -Type "NonameApp.NonameCustomModule"
    }
}

function Add-Noname-To-IIS-Sites($siteName,$nonInteractive,$Folders)
{

    $ErrorActionPreference = "Stop"
    try
    {
        # Check if siteName exist in IIS-sites list.
        if ($siteName)
        {
            $site = Get-IISSite $siteName
            if (-Not $site) { break }
        }

        Install-Pre-requisites $nonInteractive

        Create-Noname-Log
        Compile-Noname-Module

        # Loop through each IIS site and add Noname module.
        $sites = Get-IISSite
        foreach ($site in $sites)
        {

            if ((-Not $siteName) -Or ($site.Name -eq $siteName))
            {
                Write-Host ("IIS Site: '" + $site.Name + "'`n")
                # Capture the IIS Sites physical path & run the batch file for each
                $physicalPath = $site.Applications.VirtualDirectories.PhysicalPath
                $physicalPath = $physicalPath.replace("%SystemDrive%", "C:")
                Write-Host ("Running batch file against: '" + $physicalPath + "'`n")
                Add-Noname-Module
                Copy-Noname-Module-To-Site $physicalPath $Folders
                Write-Host ("Stopping site: '" + $site.Name + "'`n")
                Stop-WebSite -Name $site.Name
                Write-Host ("Starting site: '" + $site.Name + "'`n")
                Start-WebSite -Name $site.Name
                Write-Host ("Restart '" + $site.Name + "' done`n")
            }

        }
    }
    catch [System.SystemException]
    {
        Write-Host ("An error occurred.`n" + $_)
    }
}

Add-Noname-To-IIS-Sites $siteName $nonInteractive $Folders
