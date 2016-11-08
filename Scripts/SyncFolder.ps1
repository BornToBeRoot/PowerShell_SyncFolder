###############################################################################################################
# Language     :  PowerShell 5.0
# Filename     :  SyncFolder.ps1
# Autor        :  BornToBeroot
# Description  :  Synchronizes a folder (with subfolder/files) in one direction
# Repository   :  https://github.com/BornToBeRoot/PowerShell_SyncFolder
###############################################################################################################

<#
    .SYNOPSIS
    Synchronizes a folder (with subfolder/files) in one direction

    .DESCRIPTION
    Synchronizes a folder (with subfolder/files) in one direction. The follwoing options are available:
      
      1. You can synchronize two folders on your lokal system (local drive / network share)
      2. From a remote PC over a PSSession with your local system (local drive / network share)
      3. To a remote PC over a PSSession with your local system (local drive / network share)

    The advantage of the last 2 points is, that you can synchronize a folder with a remote PC which is not necessarily a member of an Active Directory domain. Only PowerShell-Remoting must be enabled and if you are not in the same subnet, you have to add on both sides the other client as TrustedHost (WinRM).

    .EXAMPLE    

    .EXAMPLE    

    .LINK
    https://github.com/BornToBeRoot/PowerShell_SyncFolder/blob/master/README.md    
#>

#Requires -Version 5.0

[CmdletBinding(DefaultParameterSetName="__AllParameterSets")]
param(
    [Parameter(
        Position=0,
        Mandatory=$true,
        HelpMessage='Source folder')]
    [String]$Source,

    [Parameter(
        Position=1,
        Mandatory=$true,
        HelpMessage='Destination folder')]
    [String]$Destination,

    [Parameter(
        ParameterSetName="ToSession",
        Position=2,
        Mandatory=$true,
        HelpMessage='Sync folder to PSSession')]
    [switch]$ToSession,

    [Parameter(
        ParameterSetName="FromSession",
        Position=2,
        Mandatory=$true,
        HelpMessage='Sync folder from PSSession')]
    [switch]$FromSession,

    [Parameter(
        ParameterSetName='ToSession',
        Mandatory=$true,
        Position=3,        
        HelpMessage='Hostname or IPv4-Address')]
    [Parameter(
        ParameterSetName='FromSession',
        Mandatory=$true,
        Position=3,        
        HelpMessage='Hostname or IPv4-Address')]
    [String]$ComputerName,

    [Parameter(
        ParameterSetName='ToSession',
		Position=4,
		HelpMessage='Credentials to authenticate agains a remote computer')]
    [Parameter(
        ParameterSetName='FromSession',
		Position=4,
		HelpMessage='Credentials to authenticate agains a remote computer')]
	[System.Management.Automation.PSCredential]
	[System.Management.Automation.CredentialAttribute()]
    $Credential
)

Begin{
    # ScriptBlock to get the folder structure
    [System.Management.Automation.ScriptBlock]$ScriptBlock_GetDirectoryStructure = {
        param(
            [String]$Path
        )

        foreach($Directory in Get-ChildItem -Path $Path -Directory -Recurse)
        {         
            $ItemPath = (($Directory.FullName).Substring($Path.Length, (($Directory.FullName.Length) - $Path.Length)) -split '\\',2)[1]

            [pscustomobject]@{
                ItemPath = $ItemPath
            }
        }
    }

    # ScriptBlock to get the file structure with LastWriteTimeUtc and Bytes
    [System.Management.Automation.ScriptBlock]$ScriptBlock_GetFileStructure = {
        param(
            [String]$Path
        )

        foreach($File in Get-ChildItem -Path $Path -File -Recurse)
        {         
            $ItemPath = (($File.FullName).Substring($Path.Length, (($File.FullName.Length) - $Path.Length)) -split '\\',2)[1]

            [pscustomobject]@{
                ItemPath = $ItemPath
                LastWriteTimeUtc = $File.LastWriteTimeUtc
                Length = $File.Length 
           }
        }
    }

    # ScriptBlock to remove files
    [System.Management.Automation.ScriptBlock]$ScriptBlock_RemoveFile = {
        param(
            [String]$Path,
            $Files2Remove,
            $VerbosePref
        )

        $VerbosePreference = $VerbosePref

        Write-Verbose "Remove $($Files2Remove.Count) files in destination:"

        foreach($File in $Files2Remove)
        {
            Write-Verbose -Message "  [-] $($File.ItemPath)"
            Remove-Item -Path (Join-Path -Path $Path -ChildPath $File.ItemPath) -Force
        }
    }

    # ScriptBlock to remove directories
    [System.Management.Automation.ScriptBlock]$ScriptBlock_RemoveDirectory = {
        param(
            [String]$Path,
            $Directories2Remove,
            $VerbosePref
        )

        $VerbosePreference = $VerbosePref

        Write-Verbose "Remove $($Directories2Remove.Count) directories in destination."

        foreach($Directory in ($Directories2Remove | Sort-Object -Property {$_.ItemPath} -Descending))
        {
            Write-Verbose -Message "  [-] $($Directory.ItemPath)"
            Remove-Item -Path (Join-Path -Path $Path -ChildPath $Directory.ItemPath) -Force
        }
    }

    #ScriptBlock to create directories
    [System.Management.Automation.ScriptBlock]$ScriptBlock_CreateDirectory = {
        param(
            [String]$Path,
            $Directories2Create,
            $VerbosePref          
        )

        $VerbosePreference = $VerbosePref

        Write-Verbose "Create $($Directories2Create.Count) directories in destination."

        foreach($Directory in ($Directories2Create | Sort-Object -Property {$_.ItemPath}) )
        {
            Write-Verbose -Message "  [+] $($Directory.ItemPath)"
            [void](New-Item -Path (Join-Path -Path $Path -ChildPath $Directory.ItemPath) -ItemType Directory)
        }
    }
}

Process{
    # If the parameter -ToSession or -FromSession is used... we have to establish a new PSSession
    try{
        if($PSBoundParameters.ContainsKey('ComputerName'))
        {
            Write-Verbose -Message "Check if ""$ComputerName"" is reachable via ICMP..."
            if(-not(Test-Connection -ComputerName $ComputerName -Count 2 -Quiet))
            {
                throw "$ComputerName is not reachable via ICMP"
            }

            Write-Verbose -Message "Try to establish connection to ""$ComputerName""..."

            if($PSBoundParameters.ContainsKey('Credential'))
            {                 
                Write-Verbose -Message "Use credentials that have been passed."
                $Session = New-PSSession -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop
            }
            else
            {
                $Session = New-PSSession -ComputerName $ComputerName -ErrorAction Stop
            } 

            if($null -eq $Session)
            {
                throw "PSSession to $ComputerName could not be established!"
            }
        }               
    }
    catch{
        throw
    }

    # Normalize paths
    $Source_Path = $Source.TrimEnd('\')
    Write-Verbose -Message "Source path is set to: ""$Source_Path"""
    
    $Destination_Path = $Destination.TrimEnd('\')
    Write-Verbose -Message "Destination path is set to: ""$Destination_Path""."

    Write-Verbose -Message "Collecting directory and file informations for source and destination..."

    # Get the folder structure and items from the source and destination path
    try{
        if($PSCmdlet.ParameterSetName -eq "ToSession")
        {            
            Write-Verbose -Message "Selected Mode: ToSession"

            $Source_Directories = Invoke-Command -ScriptBlock $ScriptBlock_GetDirectoryStructure -ArgumentList $Source_Path
            $Source_Files = Invoke-Command -ScriptBlock $ScriptBlock_GetFileStructure -ArgumentList $Source_Path
            $Destination_Directories = Invoke-Command -ScriptBlock $ScriptBlock_GetDirectoryStructure -ArgumentList $Destination_Path -Session $Session 
            $Destination_Files = Invoke-Command -ScriptBlock $ScriptBlock_GetFileStructure -ArgumentList $Destination_Path -Session $Session
        }
        elseif($PSCmdlet.ParameterSetName -eq "FromSession")
        {
            Write-Verbose -Message "Selected mode: FromSession"

            $Source_Directories = Invoke-Command -ScriptBlock $ScriptBlock_GetDirectoryStructure -ArgumentList $Source_Path -Session $Session    
            $Source_Files = Invoke-Command -ScriptBlock $ScriptBlock_GetFileStructure -ArgumentList $Source_Path -Session $Session
            $Destination_Directories = Invoke-Command -ScriptBlock $ScriptBlock_GetDirectoryStructure -ArgumentList $Destination_Path 
            $Destination_Files = Invoke-Command -ScriptBlock $ScriptBlock_GetFileStructure -ArgumentList $Destination_Path 
        }
        else 
        {
            Write-Verbose -Message "Selected mode: Normal"

            $Source_Directories = Invoke-Command -ScriptBlock $ScriptBlock_GetDirectoryStructure -ArgumentList $Source_Path
            $Source_Files = Invoke-Command -ScriptBlock $ScriptBlock_GetFileStructure -ArgumentList $Source_Path
            $Destination_Directories = Invoke-Command -ScriptBlock $ScriptBlock_GetDirectoryStructure -ArgumentList $Destination_Path   
            $Destination_Files = Invoke-Command -ScriptBlock $ScriptBlock_GetFileStructure -ArgumentList $Destination_Path
        }
    }
    catch
    {
        throw "$($_.Exception.Message)" 
    }

    Write-Verbose -Message "Found $($Source_Directories.Count) directories in Source."
    Write-Verbose -Message "Found $($Source_Files.Count) files in Source."
    Write-Verbose -Message "Found $($Destination_Directories.Count) directories in Destination."
    Write-Verbose -Message "Found $($Destination_Files.Count) files in Destination."

    Write-Verbose -Message "Compare source and destination..."

    $Files2Remove = @()
    $Directories2Remove = @()
    $Directories2Create = @()
    $Files2Copy = @()
    $Files2Overwrite = @()

    # Files to remove on destination
    foreach($Destination_File in $Destination_Files)
    {
        $FileExistsInSource = $false

        foreach($Source_File in $Source_Files)
        {
            if($Destination_File.ItemPath -eq $Source_File.ItemPath)
            {
                $FileExistsInSource = $true
            }
        }

        if($FileExistsInSource -eq $false)
        {
            $Files2Remove += $Destination_File
        }
    }    

    # Folders to remove in destination
    foreach($Destination_Directory in $Destination_Directories)
    {
        $DirectoryExistsInSource = $false

        foreach($Source_Directory in $Source_Directories)
        {
            if($Destination_Directory.ItemPath -eq $Source_Directory.ItemPath)
            {
                $DirectoryExistsInSource = $true
            }
        }

        if($DirectoryExistsInSource -eq  $false)
        {
            $Directories2Remove += $Destination_Directory
        }
    }

    # Folders to add in the destination
    foreach($Source_Directory in $Source_Directories)
    {
        $DirectoryExistsInDestination = $false

        foreach($Destination_Directory in $Destination_Directories)
        {
            if($Source_Directory.ItemPath -eq $Destination_Directory.ItemPath)
            {
                $DirectoryExistsInDestination = $true
            }
        }

        if($DirectoryExistsInDestination -eq $false)
        {
            $Directories2Create += $Source_Directory
        }
    }  

    # Files to add or overwrite
    foreach($Source_File in $Source_Files)
    {
        $FileExistsInDestination = $false
        $FileHasChanged = $false

        foreach($Destination_File in $Destination_Files)
        {
            if($Source_File.ItemPath -eq $Destination_File.ItemPath)
            {
                $FileExistsInDestination = $true
        
                if(($Source_File.LastWriteTimeUtc -ne $Destination_File.LastWriteTimeUtc) -or ($Source_File.Length -ne $Destination_File.Length))
                {
                    $FileHasChanged = $true
                }
            }
        }

        if($FileExistsInDestination -eq $false)
        {           
            $Files2Copy += $Source_File
        }

        if($FileHasChanged)
        {
            $Files2Overwrite += $Source_File
        }
    }     

    try{       
        if($Files2Remove.Count -gt 0)
        {
            if($PSCmdlet.ParameterSetName -eq "ToSession")
            {
                Invoke-Command -ScriptBlock $ScriptBlock_RemoveFile -ArgumentList $Destination_Path, $Files2Remove, $VerbosePreference -Session $Session
            }
            else 
            {
                Invoke-Command -ScriptBlock $ScriptBlock_RemoveFile -ArgumentList $Destination_Path, $Files2Remove, $VerbosePreference    
            }                
        }

        if($Directories2Remove.Count -gt 0)
        {
            if($PSCmdlet.ParameterSetName -eq "ToSession")
            {
                Invoke-Command -ScriptBlock $ScriptBlock_RemoveDirectory -ArgumentList $Destination_Path, $Directories2Remove, $VerbosePreference -Session $Session
            }
            else
            {
                Invoke-Command -ScriptBlock $ScriptBlock_RemoveDirectory -ArgumentList $Destination_Path, $Directories2Remove, $VerbosePreference
            }
        }

        if($Directories2Create.Count -gt 0)
        {
            if($PSCmdlet.ParameterSetName -eq "ToSession")
            {
                Invoke-Command -ScriptBlock $ScriptBlock_CreateDirectory -ArgumentList $Destination_Path, $Directories2Create, $VerbosePreference -Session $Session
            }
            else
            {
                Invoke-Command -ScriptBlock $ScriptBlock_CreateDirectory -ArgumentList $Destination_Path, $Directories2Create, $VerbosePreference
            }
        }

        if($Files2Copy.Count -gt 0)
        {
            # Copy the files to the destination            
            Write-Verbose "Copy $($Files2Copy.Count) files to destination:"
            foreach($File2Copy in $Files2Copy)
            {
                Write-Verbose -Message "  [+] $($File2Copy.ItemPath)"
                
                if($PSCmdlet.ParameterSetName -eq "ToSession")
                {
                    Copy-Item -Path (Join-Path -Path $Source_Path -ChildPath $File2Copy.ItemPath) -Destination (Split-Path -Path (Join-Path -Path $Destination_Path -ChildPath $File2Copy.ItemPath)) -ToSession $Session -Force
                }
                elseif($PSCmdlet.ParameterSetName -eq "FromSession")
                {
                    Copy-Item -Path (Join-Path -Path $Source_Path -ChildPath $File2Copy.ItemPath) -Destination (Split-Path -Path (Join-Path -Path $Destination_Path -ChildPath $File2Copy.ItemPath)) -FromSession $Session -Force
                }
                else 
                {
                    Copy-Item -Path (Join-Path -Path $Source_Path -ChildPath $File2Copy.ItemPath) -Destination (Split-Path -Path (Join-Path -Path $Destination_Path -ChildPath $File2Copy.ItemPath)) -Force
                }
            }      
        }

        if($Files2Overwrite.Count -gt 0)
        {
            Write-Verbose "Overwrite $($Files2Overwrite.Count) files in destination:"
            foreach($File2Overwrite in $Files2Overwrite)
            {
                Write-Verbose -Message "  [+] $($File2Overwrite.ItemPath)"
                
                if($PSCmdlet.ParameterSetName -eq "ToSession")
                {
                    Copy-Item -Path (Join-Path -Path $Source_Path -ChildPath $File2Overwrite.ItemPath) -Destination (Split-Path -Path (Join-Path -Path $Destination_Path -ChildPath $File2Overwrite.ItemPath)) -ToSession $Session -Force
                }
                elseif($PSCmdlet.ParameterSetName -eq "FromSession")
                {
                    Copy-Item -Path (Join-Path -Path $Source_Path -ChildPath $File2Overwrite.ItemPath) -Destination (Split-Path -Path (Join-Path -Path $Destination_Path -ChildPath $File2Overwrite.ItemPath)) -FromSession $Session -Force
                }
                else 
                {
                    Copy-Item -Path (Join-Path -Path $Source_Path -ChildPath $File2Overwrite.ItemPath) -Destination (Split-Path -Path (Join-Path -Path $Destination_Path -ChildPath $File2Overwrite.ItemPath)) -Force
                }
            }
        }     
    }
    catch{
        throw "$($_.Exception.Message)" 
    }

    # Close PSSession
    if($PSBoundParameters.ContainsKey('ComputerName'))
    {
        Write-Verbose "Close PSSession with ""$ComputerName""."
        Remove-PSSession -Session $Session
    }
}

End{

}