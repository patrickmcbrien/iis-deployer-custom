param ($siteName,$nonInteractive,[Parameter(Mandatory=$false)][string[]]$Folders) 

#ARGUMENTS ARE OPTIONAL allowing you to target specific folders to copy the DLL into AND/OR specific siteNames to apply Noname to the IIS config

#./deploy.ps1 -siteName pass in an IIS site to target. #CAUTION if no user input for siteName this will add Noname to ALL of the IIS sites
#./deploy.ps1 -Folders c:\test,c:\webroot\bin

#EXAMPLES  .\deploy.ps1 -Folders c:\Default -siteName "Default Web Site"
# or .\deploy.ps1 -siteName "Default Web Site" for a singles site IIS config change
# or .\deploy.ps1 -Folders c:\Default for a singles folder DLL copy and ALL IIS sites config changes
# or .\deploy.ps1 -Folders c:\Default for a single folder DLL copy with NO IIS site config changes

#Comes with no warranties
#Patrick Mcbrien
#Noname

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
    $filteredModules = Get-WebManagedModule -PSPath "IIS:\sites\$siteName" | Where-Object Name -like "*Noname*" # Check if the web-managed-modules contains Noname module for the site
    if ($filteredModules.Count -gt 0)
    {
        # The Noname IIS module is installed
        Write-Host ($filteredModules.Name + " module is already installed on the site. Skipping Noname module installation on PSPath IIS:\sites\" + $siteName + "`n")
    }
    else
    {
        # The Noname IIS module is not installed
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
        if ($siteName) # Check if siteName exists from user input
        {
            $sites = Get-IISSite $siteName #if a site is passed it will use a single site
        } else{
            $sites = Get-ChildItem IIS:\Sites\ #CAUTION if no user input this will get ALL of the IIS sites
        }
        
        Install-Pre-requisites $nonInteractive
        Write-Host "Prereqs met ...`n"   
        Copy-Noname-Module-To-Sites $Folders    #First we copy blessed DLL files to Folders if they are passed in

        foreach ($site in $sites) #loop through IIS sites
        {
            if ((-Not $siteName) -Or ($site.Name -eq $siteName))
            {
                Write-Host ("Processing IIS Site: '" + $site.Name + "'`n")
                Add-Noname-Module-Site($site) #adds the noname module to the site
                
            }
        }
    }
    catch [System.SystemException]
    {
        Write-Host ("An error occurred.`n" + $_)
    }
}

Add-Noname-To-IIS-Sites $siteName $nonInteractive $Folders
