param ($siteName,$nonInteractive,[Parameter(Mandatory=$false)][string[]]$Folders)

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


function Copy-Noname-Module-To-Sites([array]$Folders)
{

    foreach ($folder in $Folders) {
    
        $sourcePath = 'C:\Noname\NonameApp.dll'
        $destinationPath = $folder + '\NonameApp.dll'

        If(!(Test-Path -PathType container $folder))
        {  
            New-Item -ItemType Directory -Path $folder
            Write-Host ("Created a new folder" + $folder)
        }

        if (Test-Path -Path $folder -PathType Container) {
            If (Test-Path -Path $destinationPath ) {
                Write-Host ($destinationPath + " ALREADY exists. Not copying the DLL. `n")
            }else {
                Write-Host ("DLL Not found so copying blessed Noname DLL from source path " + $sourcePath + " into the dest Path " + $destinationPath + ". `n")
                Copy-Item -Path $sourcePath -Destination $destinationPath -Force
            }
        } else {
            Write-Host "Folder '$folder' does not exist or is not accessible."

        }
    }

}

function Add-Noname-Module-Site($site)
{
    $siteName = $site.Name
    Write-Host ("Adding noname module locally for site: "+$siteName+".`n")
    $filteredModules = Get-WebManagedModule -PSPath "IIS:\sites\$siteName" | Where-Object Name -like "*Noname*"
    # Check if the web-managed-modules contains Noname module for the 
    if ($filteredModules.Count -gt 0)
    {
        # The module is installed
        Write-Host ($filteredModules.Name + " module is already installed on the site. Skipping Noname module installation on PSPath IIS:\sites\" + $siteName + "`n")
    }
    else
    {
        # The module is not installed
        Write-Host ("Noname module is not installed, so let's install it on PSPath IIS:\sites\" +$siteName+"`n")
        New-WebManagedModule -Name "NonameCustomModule" -Type "NonameApp.NonameCustomModule" -PSPath "IIS:\sites\$siteName"

        Write-Host ("Stopping site: '" + $siteName + "'`n")
        Stop-WebSite -Name $siteName
        Write-Host ("Starting site: '" + $siteName + "'`n")
        Start-WebSite -Name $siteName
        Write-Host ("Restart '" + $siteName + "' done`n")
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
            $sites = Get-IISSite $siteName 
        } else{
            $sites = Get-ChildItem IIS:\Sites\
        }

        Install-Pre-requisites $nonInteractive
        Write-Host "Prereqs met ...`n"   
      
        #First we copy DLL files to Folders
        Copy-Noname-Module-To-Sites $Folders

        foreach ($site in $sites)
        {
            if ((-Not $siteName) -Or ($site.Name -eq $siteName))
            {
                Write-Host ("Processing IIS Site: '" + $site.Name + "'`n")
                Add-Noname-Module-Site($site)
                
            }
        }
    }
    catch [System.SystemException]
    {
        Write-Host ("An error occurred.`n" + $_)
    }
}

Add-Noname-To-IIS-Sites $siteName $nonInteractive $Folders
