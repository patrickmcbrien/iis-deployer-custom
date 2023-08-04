#USAGE
#NOTE! FIRST IMPORT THE MODULE, THEN RUN COMMANDS

#Import-Module .\noname-deploy-module.psm1 -Force

#ADD NONAME MODULE TO ALL IIS APPLICATIONS/SITES
#Add-Noname-Module-Site -siteName "Dogfood" -autoApprove "y" 

#ADD NONAME MODULE ONLY TO THE IIS APPLICATION AND SITE PASSED
#Add-Noname-Module-Application -siteName "Dogfood" -appName "testapp" -autoApprove "y" 

#REMOVE NONAME MODULE FROM ALL SITES

#Remove-Noname-Module-Site -siteName "Dogfood"

function Verify-Site-Name($siteName)
{
    # Check if siteName exist in Windows server.
    $sites = Get-IISSite
    if (-Not $sites) {
        throw "[ERROR] IIS site does not exists in this server!`n" + $_
    }
    if ($siteName)
    {
        # Check if siteName exist in IIS-sites list.
        $siteFound = $false
        $sites = Get-IISSite $siteName
        foreach ($site in $sites)
        {
            if ($site.Name -eq $siteName)
            {
                $siteFound = $true
                break
            }
        }
        if (!$siteFound)
        { throw "[ERROR] IIS site name: '$siteName' does not exists in this server!`n" + $_ }
    }
}

function Verify-App-Name($siteName, $appName) {

}

function Install-Pre-requisites($autoApprove)
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
            Write-Host -ForegroundColor Cyan "'$item' already installed"
        }
    }
    #  if one of the pre-requisites didn't install, ask ack from the user to install it.
    if ($nonInstalledRequirements)
    {
        if ($autoApprove -ne "y" -or $autoApprove -ne "Y")
        {
            write-host -ForegroundColor Yellow "The following requirements are not installed`n'$nonInstalledRequirements'`nDo you want to install them? [y/n]"
            $autoApprove = Read-Host
        }
        if ($autoApprove -eq "y" -or $autoApprove -eq "Y")
        {
            foreach ($requirement in $nonInstalledRequirements)
            {
                Write-Host -ForegroundColor Cyan "Installing '$requirement'"
                Install-WindowsFeature -Name $requirement
            }
        }
        else{
            throw "The following requirements cannot be installed.`n $nonInstalledRequirements"
        }
    }
}

function Create-Noname-Log
{
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
    $assemblyName = Join-Path $PSScriptRoot 'NonameApp.dll'
    & $frameworkPath /t:library /out:$assemblyName /o $modulePath /r:System.Web.dll
}

function Copy-Noname-Module-To-Bin([string] $physicalPath)
{
    $binDir = Join-Path $physicalPath 'bin'
    if (!(Test-Path $binDir)) {
        New-Item -ItemType Directory -Path $binDir | Out-Null
    }
    $sourcePath = Join-Path $PSScriptRoot 'NonameApp.dll'
    $destinationPath = Join-Path $binDir 'NonameApp.dll'

    Copy-Item -Path $sourcePath -Destination $destinationPath -Force
}
function Is-Integrated-Mode($siteName)
{
    # Check if site application-pool is Integrated pipeline mode
    $siteAppPool = (Get-WebSite -Name $siteName).ApplicationPool
    $integratedSites = Get-IISAppPool | Where-Object { $_.ManagedPipelineMode -eq 'Integrated' }
    foreach ($integratedSite in $integratedSites)
    {
        if ($integratedSite.Name -eq $siteAppPool)
        {
            return $true
        }
    }
    return $false
}
function Add-Noname-Module-To-App($siteName)
{
    Write-Host "Site Name for adding module to app $siteName"
    $module = Get-WebConfiguration -Filter "/system.webServer/modules/add" -PSPath "IIS:\Sites\$siteName" | Where-Object Name -eq 'NonameCustomModule'
    
    if (!$module)
    {
        Add-WebConfiguration -Filter "/system.webServer/modules" -PSPath "IIS:\Sites\$siteName" -Value @{
            name = "NonameCustomModule"
            type = "NonameApp.NonameCustomModule"
        } -Force
        Write-Host -ForegroundColor Cyan "NonameCustomModule module added to the '$siteName' site."
    }
    else {
        Write-Host -ForegroundColor Cyan "NonameCustomModule module already exists in the '$siteName' site."
    }
}

function Remove-Noname-Module-From-App($siteName)
{
    $module = Get-WebConfiguration -Filter "/system.webServer/modules/add" -PSPath "IIS:\Sites\$siteName" | Where-Object Name -eq 'NonameCustomModule'
    if ($module)
    {
        Remove-WebManagedModule -Name "NonameCustomModule" -PSPath "IIS:\Sites\$siteName"
        Write-Host -ForegroundColor Cyan "NonameCustomModule module removed from '$siteName' site.`n"
    }
    else {
        Write-Host -ForegroundColor Yellow "NonameCustomModule does not exists in '$siteName' site.`n"
    }
}

function Add-Noname-Module-Application([string]$siteName, [string]$appName, $autoApprove)
{
    try
    {
        $ErrorActionPreference = "Stop"
        Verify-Site-Name $siteName
        Install-Pre-requisites $autoApprove

        Create-Noname-Log
        Compile-Noname-Module #compile the module from C# to create the DLL file

        if (! (Is-Integrated-Mode $siteName))
        {
            Write-Host -ForegroundColor Yellow "'$siteName' is Classic pipeline mode. we can't add Noname module.`n"
            continue
        }

        # PowerShell  Check to make sure we have appcmd installed
        $WantFile =  "system32\inetsrv\appcmd.exe"
        $FileExists = Test-Path $WantFile
        If ($FileExists -eq $True) {Write-Host "Found Appcmd.exe, proceeding"}
        Else {
            Write-Host "Fatal Error: Please install AppCmd.exe. This is a requirement for Noname. No Appcmd at this location "$Env:windir"system32\inetsrv\ so exiting powershell noname installation script"
            break
        }

        $apps = Get-WebApplication -Site $siteName -Name $appName
        if (-Not $apps) {
            Write-Host "Fatal Error: Application to found for site $siteName and application $appName"
            break
        }

        foreach ($app in $apps) {

            Write-Host "Physical Path of IIS application: " $app.physicalPath
            $appPhysicalPath=$app.physicalPath.replace("%SystemDrive%", "C:")
            Copy-Noname-Module-To-Bin $appPhysicalPath 
            $appPathIIS = ($siteName + "/" + $appName).trim() #for example, "My Default Site/Cats"
                    
            $filteredModules = Get-WebManagedModule -Name "NonameCustomModule" -PSPath "IIS:\sites\$siteName\$appName"
            if ($filteredModules.Count -gt 0)
            {
                Write-Host("Noname module already found on IIS application $appName")
                Write-Host("Exiting")
                break
            } else{
                Write-Host ("No IIS module found on application: " + $appName + "'`n")
                $Env:windir"system32\inetsrv\appcmd.exe" set config $appPathIIS -section:system.webServer/modules /+`"["name='NonameCustomModule',type='NonameApp.NonameCustomModule'"]          
                Write-Host ("Module installed locally on Noname IIS application $appName")
            } 
        }

        Stop-WebSite -Name $siteName
        Start-WebSite -Name $siteName
        Write-Host -ForegroundColor Cyan "Restart '$siteName' completed successfully`n"
        Write-Host -ForegroundColor Green "Install Noname module completed successfully"
    }
    catch [System.SystemException]
    {
        $message = $_
        Write-Error "[ERROR] An error occurred.`n $message"
    }
}

function Add-Noname-Module-Site($siteName,$autoApprove)
{
    try
    {
        $ErrorActionPreference = "Stop"
        Verify-Site-Name $siteName
        Install-Pre-requisites $autoApprove

        Create-Noname-Log
        Compile-Noname-Module

        # Loop through each IIS site and add Noname module.
        $sites = Get-IISSite
        foreach ($site in $sites)
        {
            if ((-Not $siteName) -Or ($site.Name -eq $siteName))
            {
                Write-Host -ForegroundColor Cyan "IIS Site Name: '$site'"
                if (! (Is-Integrated-Mode $site.Name))
                {
                    Write-Host -ForegroundColor Yellow "'$site' is Classic pipeline mode. we can't add Noname module.`n"
                    continue
                }

                Add-Noname-Module-To-App $site.Name

                # Capture the IIS Sites physical path & run the batch file for each
                $physicalPaths = $site.Applications.VirtualDirectories.PhysicalPath
                
                Write-Host "Physical Paths: " $physicalPaths

                foreach ($physicalPath in $physicalPaths) {
                    Write-Host "Physical Path: " $physicalPath
                    $physicalPath = $physicalPath.replace("%SystemDrive%", "C:")
                    Write-Host -ForegroundColor Cyan "IIS Site Path: '$physicalPath'"
                    Copy-Noname-Module-To-Site $physicalPath #CAN ALSO BE AN APPLICATION UNDER THE SITE.
                }
                
                Stop-WebSite -Name $site.Name
                Start-WebSite -Name $site.Name
                Write-Host -ForegroundColor Cyan "Restart '$site' completed successfully`n"
        
            }
        
        
        }
        Write-Host -ForegroundColor Green "Install Noname module completed successfully"
    }
    catch [System.SystemException]
    {
        $message = $_
        Write-Error "[ERROR] An error occurred.`n $message"
    }
}


function Remove-Noname-Module-Site($siteName)
{
    try
    {
        $ErrorActionPreference = "Stop"
        Verify-Site-Name $siteName
        # Loop through each IIS site and add Noname module.
        $sites = Get-IISSite
        foreach ($site in $sites)
        {
            if (! (Is-Integrated-Mode $site.Name))
            {
                Write-Host -ForegroundColor Yellow "'$site' is Classic pipeline mode. Skipping.`n"
                continue
            }
            if ((-Not $siteName) -Or ($site.Name -eq $siteName))
            {
                Remove-Noname-Module-From-App $site.Name
            }
        }
        Write-Host -ForegroundColor Green "Remove Noname module completed successfully"
    }
    catch [System.SystemException]
    {
        $message = $_
        Write-Error "[ERROR] An error occurred.`n $message"
    }
}
function Remove-Noname-Module-Application($siteName)
{
    try
    {
        $ErrorActionPreference = "Stop"
        Verify-Site-Name $siteName
        # Loop through each IIS site and add Noname module.
        $sites = Get-IISSite
        foreach ($site in $sites)
        {
            if (! (Is-Integrated-Mode $site.Name))
            {
                Write-Host -ForegroundColor Yellow "'$site' is Classic pipeline mode. Skipping.`n"
                continue
            }
            if ((-Not $siteName) -Or ($site.Name -eq $siteName))
            {
                Remove-Noname-Module-From-App $site.Name
            }
        }
        Write-Host -ForegroundColor Green "Remove Noname module completed successfully"
    }
    catch [System.SystemException]
    {
        $message = $_
        Write-Error "[ERROR] An error occurred.`n $message"
    }
}

function Verify-Noname-Installation-Site($siteName) {

}
function Verify-Noname-Installation-App($siteName) {

}
Import-Module WebAdministration
Export-ModuleMember -Function Add-Noname-Module-Application
Export-ModuleMember -Function Add-Noname-Module-Site
Export-ModuleMember -Function Remove-Noname-Module-Application
Export-ModuleMember -Function Remove-Noname-Module-Site
Export-ModuleMember -Function Verify-Noname-Installation-Site


