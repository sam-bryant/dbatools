﻿
Function Find-DbaOrphanedFile
{
<#
.SYNOPSIS 
Find-DbaOrphanedFile moves/removes orphaned database files

.DESCRIPTION
Get all the database files for all the database for the instance
Get the various directories of the instance and get all the present database files.
Compare which the two lists to see if there are any orphaned files and return the list

.PARAMETER SqlServer
The SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

.PARAMETER SourceDirectory
Used to specify extra directories to search through besides the default data and log directories

.NOTES 
Author: Sander Stad (@sqlstad), sqlstad.nl
Requires: sysadmin access on SQL Servers
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)

Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Find-DbaOrphanedFile

.EXAMPLE
Find-DbaOrphanedFile -SqlServer sqlserver2014a
Copies all policies and conditions from sqlserver2014a to sqlcluster, using Windows credentials. 

.EXAMPLE   
Find-DbaOrphanedFile -SqlServer sqlserver2014a -SqlCredential $cred
Does this, using SQL credentials for sqlserver2014a and Windows credentials for sql instance.

.EXAMPLE   
Find-DbaOrphanedFile -SqlServer sqlserver2014 -Sourcedirectory 'C:\Dir1', 'C:\Dir2'
Finds the orphaned files in the default directories but also the extra ones
	

#>
	
	# This is a sample. Please continue to use aliases for discoverability. Also keep the [object] type for sqlserver.
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[object]$SqlCredential,
        [parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [string[]]$SourceDirectory
	)
	
    DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabases -SqlServer $SqlServer -SqlCredential $SqlCredential } }
	
	# BEGIN is for private functions and starting connections. When using the pipeline, stuff in here will be executed first and only once.
	
	BEGIN
	{
        
        function Get-SqlFileStructure
        {
            param
            (
                [Parameter(Mandatory = $true, Position=1)]
                [ValidateNotNullOrEmpty()]
                [Alias("server")]
                [Microsoft.SqlServer.Management.Smo.SqlSmoObject]$smoserver
            )

	        if ($smoserver.versionMajor -eq 8)
	        {
		        $sql = "select DB_NAME (dbid) as dbname, name, filename, CAST(mf.Size * 8 AS DECIMAL(20,2)) AS sizeKB, '' AS Drive, '' AS DestinationFolderPath, groupid from sysaltfiles"
	        }
	        else
	        {
		        $sql = "SELECT db.name AS dbname, type_desc AS FileType, mf.name, Physical_Name AS filename, CAST(mf.Size * 8 AS DECIMAL(20,2)) AS sizeKB, '' AS Drive, '' AS DestinationFolderPath FROM sys.master_files mf INNER JOIN  sys.databases db ON db.database_id = mf.database_id"
	        }
			
	        $dbfiletable = $smoserver.ConnectionContext.ExecuteWithResults($sql)
	        $ftfiletable = $dbfiletable.Tables[0].Clone()
	        $dbfiletable.Tables[0].TableName = "data"
			
	        foreach ($db in $databaselist)
	        {
		        # Add support for Full Text Catalogs in Sql Server 2005 and below
		        if ($server.VersionMajor -lt 10)
		        {
			        #$dbname = $db.name
			        $fttable = $null = $smoserver.Databases[$database].ExecuteWithResults('sp_help_fulltext_catalogs')
					
			        foreach ($ftc in $fttable.Tables[0].rows)
			        {
				        $name = $ftc.name
				        $physical = $ftc.Path
				        $logical = "sysft_$name"
				        $null = $ftfiletable.Rows.add($database, "FULLTEXT", $logical, $physical)
			        }
		        }
	        }
			
	        $null = $dbfiletable.Tables.Add($ftfiletable)
	        return $dbfiletable
        }

        # Get the servername from the sqlinstance parameter
        if($SqlServer.Contains('\'))
        {
            $servername = $SqlServer.Split('\')[0]
        }
        else
        {
            $servername = $SqlServer
        }

        # Check if the servername is the local server
        if($env:computername -eq $servername)
        {
            # Check if the user is executing the function in elevated mode
            if(-not ((New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator))) 
            {
	            Write-Host "You must run Windows PowerShell as Administrator - Elevated Mode"
	            Throw
            }

            # Set the method to locally
            $method = 'local'
        }
        else
        {
            # Set the method to remote
            $method = 'remote'
        }

		#Write-Output "Attempting to connect to SQL Server.."
		
		$sourceserver = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential
		$source = $sourceserver.DomainInstanceName

	}
	
	# PROCESS is for processing stuff. If using the pipeline, the things in here will be executed repeatedly.
	PROCESS
	{
        #Write-Output "Retrieving active database files.."

        # Get all the database files
        $databasefiles = Get-SqlFileStructure -server $sourceserver

        # Check if there are any database files retrieved
        if($databasefiles.count -ge 1)
        {
            # Create the orphaned files variable
            $orphanedfiles = @() 

            # Getthe default data and log directories from the instance
            $SourceDirectory += $sourceserver.RootDirectory + "\DATA"

            # Check if the default file path is set
            if (($sourceserver.Settings.DefaultFile).Length -eq 0) 
            {
	            $SourceDirectory += $sourceserver.Information.MasterDBPath
	        }
            else
            {
                $SourceDirectory += $sourceserver.Settings.DefaultFile
            }

            # Check if the default log path is set
	        if (($sourceserver.Settings.DefaultLog).Length -eq 0) {
	            $SourceDirectory = $sourceserver.Information.MasterDBLogPath
	        }
            else
            {
                $SourceDirectory += $sourceserver.Settings.DefaultLog
            }

            # Create the array to hold the files on disk
            $diskfiles = @()

            # Loop through each of the directories and get all the data and log file related files
            foreach($directory in $SourceDirectory)
            {
                # Cleanup directory
                if($directory.EndsWith("\")) 
                {
                    $directory = $directory.TrimEnd("\")
                }
                
                # Check the method and change to UNC admin paths
                if($method -eq 'remote')
                {
                    # Set the directory to administrative UNC paths
                    $directory = Join-AdminUnc -servername $servername -FilePath $directory

                }
                
                # Check if the path exists
                if(Test-Path $directory)
                {
                    # Get the files on disk
                    $diskfiles += Get-ChildItem -Path "$directory\*.*" -Include *.mdf,*.ldf,*.ndf 
                }
                
            }

            # If there are files found
            if($diskfiles.count -ge 1)
            {
                switch($method)
                {
                    'local' { $dbfiles = $databasefiles.Tables[0].filename }
                    'remote' { $dbfiles = $databasefiles.Tables[0].filename | % {$_ -replace ':','$'} | % {"\\$servername\" + $_} }
                }

                # Compare the two lists and save the items that are not in the database file list 
                $orphanedfiles = (Compare-Object -ReferenceObject ($dbfiles) -DifferenceObject $diskfiles.FullName).InputObject
            }
                
            return $orphanedfiles
        }
    }
		
	# END is to disconnect from servers and finish up the script. When using the pipeline, things in here will be executed last and only once.
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
			
	} 
}