﻿function Get-DbaDatabaseEncryption {
<#
.SYNOPSIS
Returns a summary of encrption used on databases based to it.

.DESCRIPTION
Shows if a database has Transparaent Data encrption, any certificates, asymmetric keys or symmetric keys with details for each.

.PARAMETER SqlServer
SQLServer name or SMO object representing the SQL Server to connect to. This can be a
collection and recieve pipeline input

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, currend Windows login will be used.

.PARAMETER Database
Define the database you wish to search

.NOTES 
Original Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.	

.LINK
https://dbatools.io/Get-DbaDatabaseEncryption

.EXAMPLE
Get-DbaDatabaseEncryption -SqlServer DEV01
List all encrpytion found on the instance by database

.EXAMPLE
Get-DbaDatabaseEncryption -SqlServer DEV01 -Database MyDB
List all encrption found in MyDB 
#>
	[CmdletBinding()]
	param ([parameter(ValueFromPipeline, Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[switch]$IncludeSystemDBs)
	
	DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabases -SqlServer $SqlServer[0] -SqlCredential $SourceSqlCredential } }
	
	BEGIN
	{
		$databases = $psboundparameters.Databases
        $exclude = $psboundparameters.Exclude
    }

	PROCESS
	{
		foreach ($s in $SqlServer)
		{
			#For each SQL Server in collection, connect and get SMO object
			Write-Verbose "Connecting to $s"
			$server = Connect-SqlServer $s -SqlCredential $SqlCredential
			#If IncludeSystemDBs is true, include systemdbs
			#only look at online databases (Status equal normal)
			try
			{
				if ($databases.length -gt 0)
				{
					$dbs = $server.Databases | Where-Object { $databases -contains $_.Name }
				}
				elseif ($IncludeSystemDBs)
				{
					$dbs = $server.Databases | Where-Object { $_.status -eq 'Normal' }
				}
				else
				{
					$dbs = $server.Databases | Where-Object { $_.status -eq 'Normal' -and $_.IsSystemObject -eq 0 }
				}
				
				if ($exclude.length -gt 0)
				{
					$dbs = $dbs | Where-Object { $exclude -notcontains $_.Name }
				}
			}
			catch
			{
				Write-Exception $_
				throw "Unable to gather dbs for $($s.name)"
				continue
			}
			
			foreach ($db in $dbs)
			{    
                if ($db.EncryptionEnabled -eq $true)
                {
       
                [PSCustomObject]@{
                        Server = $server.name
                        Instance = $server.InstanceName
                        Database = $db
                        Encryption = "EncryptionEnabled (tde)"
                        Name =  $null
                        LastBackup = $null 
                        PrivateKeyEncryptionType = $null
                        EncryptionAlgorithm = $null
                        KeyLength = $null
                        Owner = $null			
                    } 
                   
                }

                foreach ($cert in $db.Certificates)
                {
    
                    [PSCustomObject]@{
                        Server = $server.name
                        Instance = $server.InstanceName
                        Database = $db
                        Encryption = "Certificate"
                        Name =  $cert.Name
                        LastBackup = $cert.LastBackupDate
                        PrivateKeyEncryptionType = $cert.PrivateKeyEncryptionType
                        EncryptionAlgorithm = $null
                        KeyLength = $null
                        Owner = $cert.Owner			
                    }
                    
                }
                
                foreach ($ak in $db.AsymmetricKeys)
                {
  
                    [PSCustomObject]@{
                        Server = $server.name
                        Instance = $server.InstanceName
                        Database = $db
                        Encryption = "Asymentric key"
                        Name =  $ak.Name
                        LastBackup = $null
                        PrivateKeyEncryptionType = $ak.PrivateKeyEncryptionType
                        EncryptionAlgorithm = $ak.KeyEncryptionAlgorithm
                        KeyLength = $ak.KeyLength
                        Owner = $ak.Owner	
                    }
                    
                }
                foreach ($sk in $db.SymmetricKeys)
                {

                    [PSCustomObject]@{
                        Server = $server.name
                        Instance = $server.InstanceName
                        Database = $db
                        Encryption = "Symmetric key"
                        Name =  $sk.Name
                        LastBackup = $null
                        PrivateKeyEncryptionType = $sk.PrivateKeyEncryptionType
                        EncryptionAlgorithm = $ak.EncryptionAlgorithm
                        KeyLength = $sk.KeyLength
                        Owner = $sk.Owner	
                    }
                }
            }
        }  
    }		
}

