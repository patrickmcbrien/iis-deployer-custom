param ([Parameter(Mandatory=$true)]$siteName,[Parameter(Mandatory=$true)]$appName,[Parameter(Mandatory=$true)]$folderName, $nonInteractive) 

#./blessed-deploy.ps1 -siteName "Default Web Site" -appName "Cats" -folderName "c:\Brand New Folder"

# Updated version: https://github.com/patrickmcbrien/iis-deployer-custom/blob/main/blessed-deploy.ps1

# This script now installs the Noname module at the application level and not at the site level
# If the folder passed in does not exist, the script will create the folder
# If the DLL does not exist in the folder passed to the script, then it will copy the dll into the folder from c:\Noname and then also install the IIS configuration at the application level for the site and app passed
# If the DLL exists in the folder passed, the script does nothing at all. I could still check the IIS application for the noname module regardless of dll existence but currently the script is not setup for this(easy change if this is desired)
# The IIS site will be restarted only if the noname module is installed to the iis application
# Usage: #./blessed-deploy.ps1 -siteName "Default Web Site" -appName "Cats" -folderName "c:\Brand New Folder"

# All three arguments are required and the script does one site/app/folder combination at a time. This should make scripting a list a breeze.
#Comes with no warranties
#Patrick Mcbrien
#Noname


function Add-Noname-To-IIS-Applications($siteName,$appName,$folderName,$nonInteractive)
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
        
        #Install-Pre-requisites $nonInteractive
        Write-Host "Prereqs met ..."   
        Write-Host ("Copying the DLL into " + $folderName)
        
        $sourcePath = 'C:\Noname\NonameApp.dll'
        $destinationPath = $folderName + '\NonameApp.dll'
        
        If(!(Test-Path -PathType container $folderName))
        {  
            New-Item -ItemType Directory -Path $folderName
            Write-Host ("Created a new folder because it does not exist at " + $folderName)
        }
        
        if (Test-Path -Path $folderName -PathType Container) {
            If (Test-Path -Path $destinationPath ) {
                Write-Host ($destinationPath + " folder already exists. Not copying the DLL or installing the IIS module at application level. `n")
            }else {
                Write-Host ("DLL Not found so copying blessed Noname DLL from source path " + $sourcePath + " into the dest Path " + $destinationPath + ". `n")
                Copy-Item -Path $sourcePath -Destination $destinationPath -Force
                
                if ($appName) {
                    Write-Host ("Installing the module into the IIS Application: '" + $siteName + "/" + $appName + "'`n")
                    $appPath = ($siteName + "/" + $appName).trim() #for example, "My Default Site/Cats"
                    
                    $filteredModules = Get-WebManagedModule -Name "NonameCustomModule" -PSPath "IIS:\sites\$siteName\$appName"
                    if ($filteredModules.Count -gt 0)
                    {
                        Write-Host("Noname already found on application located at " + $appPath)
                    } else{
                    Write-Host ("No IIS module found on application: " + $appPath + "'`n")
                    C:\windows\system32\inetsrv\appcmd.exe set config $appPath -section:system.webServer/modules /+`"["name='NonameCustomModule',type='NonameApp.NonameCustomModule'"]  
                    
                    Write-Host ("Stopping site: '" + $siteName + "'`n")
                    Stop-WebSite -Name $siteName
                    Write-Host ("Starting site: '" + $siteName + "'`n")
                    Start-WebSite -Name $siteName
                    Write-Host ("Restart '" + $siteName + "' done`n")
                    }
                }

            }
        } else {
            Write-Host "Folder '$folderName' does not exist or is not accessible."
            
        }
        
    }
    catch [System.SystemException]
    {
            Write-Host ("An error occurred.`n" + $_)
    }
}
        
        Add-Noname-To-IIS-Applications $siteName $appName $folderName $nonInteractive
        
