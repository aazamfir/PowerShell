  #######################################################################################
##
## PerfmonCollector.ps1
##
## Schedules Perfmon collection on servers with the Perfmon flag in t_monitoring set to 1 
## 
  #######################################################################################
 

## Function to return a sql query, return the results in an array.
function SQL-Query{
	param([string]$Query,
	[string]$SqlServer = $DEFAULT_SQL_SERVER,
	[string]$DB = $DEFAULT_SQL_DB,
	[string]$RecordSeparator = "`t")

	$conn_options = ("Data Source=$SqlServer; Initial Catalog=$DB;" + "Integrated Security=SSPI")
	$conn = New-Object System.Data.SqlClient.SqlConnection($conn_options)
	$conn.Open()

	$sqlCmd = New-Object System.Data.SqlClient.SqlCommand
	$sqlCmd.CommandTimeout = "300"
	$sqlCmd.CommandText = $Query
	$sqlCmd.Connection = $conn

	$reader = $sqlCmd.ExecuteReader()
	if(-not $?) {#error logging
	$lineno = Get-CurrentLineNumber
	./logerror.ps1  $Output $date $lineno $title 
	}
	[array]$serverArray
	$arrayCount = 0
	while($reader.Read()){
		$serverArray += ,($reader.GetValue(0))
		$arrayCount++
	}
	$serverArray
}
   
function SQL-NONQuery{
	param([string]$Statement,
	[string]$SqlServer = $DEFAULT_SQL_SERVER,
	[string]$DB = $DEFAULT_SQL_DB )

	$conn_options = ("Data Source=$SqlServer; Initial Catalog=$DB;" + "Integrated Security=SSPI")
	$conn = New-Object System.Data.SqlClient.SqlConnection($conn_options)
	$conn.Open()

	$cmd = $conn.CreateCommand()
	$cmd.CommandText = $Statement
	$returnquery = $cmd.ExecuteNonQuery()
	if(-not $?) {

	$lineno = Get-CurrentLineNumber
	#e:\dexma\support\logerror.ps1  $Output $date $lineno $title  
	./logerror.ps1  $Output $date $lineno $title
	}
	$returnquery
}

function Txt-extract{
	param([string]$txtName)
	$returnArray = Get-Content $txtname
	return $returnArray
}
 
function Get-CurrentLineNumber { 
	$lineno = $MyInvocation.ScriptLineNumber 
	$lineno = $lineno -2
	$lineno
}


#function NEW-SHARE ($Foldername, $Sharename) {
#	# Test for existence of folder, if not there then create it
#	if ( ! (TEST-PATH $Foldername) ) 
#		{
#		NEW-ITEM $Foldername -type Directory
#		$Shares=[WMICLASS]"WIN32_Share"
#		$Shares.Create($Foldername,$Sharename,0)
#		}
#    # Create Share but check to make sure it isn’t already there
##    if ( ! (GET-WMIOBJECT Win32_Share -ComputerName '$server' -filter “name=$Sharename”) ) 
##		{
##		$Shares=[WMICLASS]"WIN32_Share"
##		$Shares.Create($Foldername,$Sharename,0)
##    	}
#}

# // New-Share: Creates new Share on local or remote PC, with custom permissions.
# // Required Parameters: FolderPath, ShareName
# //
# // New-ACE: Creates ACE Objects, for use when running New-Share.
# // Required Parameters: Name, Domain
# //
# // New-SecurityDescriptor: used by New-Share to prepare the permissions.
# // Required Parameters: ACEs
#//
# // Usage Examples:  
# // New-Share -FolderPath "C:\Temp" -ShareName "Temp" -ACEs $ACE,$ACE2  -Description "Test Description" -Computer "localhost"
# // Sharing of folder C:\Temp, with the Name "Temp". ACE's (Permissions) are sent via the -ACEs parameter.
# // Create them with New-ACE and send one  or more, seperated by comma (or create an array and use that)
#a group ACE, containing Group info, please notice the -Group switch
#$ACE = New-ACE -Name "Domain Users" -Domain "CORETECH" -Permission "Read" -Group
##a user ACE.
#$ACE2 = New-ACE -Name "CCO" -Domain "CORETECH" -Permission "Full"

Function New-SecurityDescriptor (
$ACEs = (throw "Missing one or more Trustees"), 
[string] $ComputerName = ".")
{
	#Create SeCDesc object
	$SecDesc = ([WMIClass] "\\$ComputerName\root\cimv2:Win32_SecurityDescriptor").CreateInstance()
	#Check if input is an array or not.
	if ($ACEs -is [System.Array])
	{
		#Add Each ACE from the ACE array
		foreach ($ACE in $ACEs )
		{
			$SecDesc.DACL += $ACE.psobject.baseobject
		}
	}
	else
	{
		#Add the ACE 
		$SecDesc.DACL =  $ACEs
	}
	#Return the security Descriptor
	return $SecDesc
}


Function New-ACE (
	[string] $Name = (throw "Please provide user/group name for trustee"),
	[string] $Domain = (throw "Please provide Domain name for trustee"), 
	[string] $Permission = "Read",
	[string] $ComputerName = ".",
	[switch] $Group = $false)
{
	#Create the Trusteee Object
	$Trustee = ([WMIClass] "\\$ComputerName\root\cimv2:Win32_Trustee").CreateInstance()
	#Search for the user or group, depending on the -Group switch
	if (!$group)
		{ $account = [WMI] "\\$ComputerName\root\cimv2:Win32_Account.Name='$Name',Domain='$Domain'" }
	else
		{ $account = [WMI] "\\$ComputerName\root\cimv2:Win32_Group.Name='$Name',Domain='$Domain'" }
	#Get the SID for the found account.
	$accountSID = [WMI] "\\$ComputerName\root\cimv2:Win32_SID.SID='$($account.sid)'"
	#Setup Trusteee object
	$Trustee.Domain = $Domain
	$Trustee.Name = $Name
	$Trustee.SID = $accountSID.BinaryRepresentation
	#Create ACE (Access Control List) object.
	$ACE = ([WMIClass] "\\$ComputerName\root\cimv2:Win32_ACE").CreateInstance()
	#Select the AccessMask depending on the -Permission parameter
	switch ($Permission)
	{
		"Read"		{ $ACE.AccessMask = 1179817 }
		"Change"	{ $ACE.AccessMask = 1245631 }
		"Full"		{ $ACE.AccessMask = 2032127 }
		default { throw "$Permission is not a supported permission value. Possible values are 'Read','Change','Full'" }
	}
	#Setup the rest of the ACE.
	$ACE.AceFlags = 3
	$ACE.AceType = 0
	$ACE.Trustee = $Trustee
	#Return the ACE
	return $ACE
}

Function New-Share (
	[string] $FolderPath = (throw "Please provide the share folder path (FolderPath)")
	, [string] $ShareName = (throw "Please provide the Share Name")
	, $ACEs
	, [string] $Description = ""
	, [string] $ComputerName = ".")
{
	#Start the Text for the message.
	$text = "$ShareName ($FolderPath): "
	#Package the SecurityDescriptor via the New-SecurityDescriptor Function.
	$SecDesc = New-SecurityDescriptor $ACEs -ComputerName $ComputerName
	#Create the share via WMI, get the return code and create the return message.
	if ( ! (GET-WMIOBJECT Win32_Share -ComputerName $ComputerName -filter "name='$Sharename'") )
		{
		$Share = [WMICLASS] "\\$ComputerName\Root\Cimv2:Win32_Share"
		$result = $Share.Create($FolderPath, $ShareName, 0, $NULL , $Description, $false , $SecDesc)
		}
	switch ($result.ReturnValue)
	{
		0 {$text += "has been success fully created" }
		2 {$text += "Error 2: Access Denied" }
		8 {$text += "Error 8: Unknown Failure" }
		9 {$text += "Error 9: Invalid Name"}
		10 {$text += "Error 10: Invalid Level" }
		21 {$text += "Error 21: Invalid Parameter" }
		22 {$text += "Error 22 : Duplicate Share"}
		23 {$text += "Error 23: Redirected Path" }
		24 {$text += "Error 24: Unknown Device or Directory" }
		25 {$text += "Error 25: Net Name Not Found" }
	}
	#Create Custom return object and Add results
	$return = New-Object System.Object
	$return | Add-Member -type NoteProperty -name ReturnCode -value $result.ReturnValue
	$return | Add-Member -type NoteProperty -name Message -value $text	
	#Return result object
	$return
}


###################
##Start Script Here
###################

$ENV = $args[0]

if ($ENV -eq $null){
    $ENV = "PROD"
    }
    
switch ($ENV) 
	{
	"PROD"{ $DBServer 		= 	"PSQLRPT24"; 
			$DB 			= 	"status"; 
			$ServerQuery	= 	"SELECT server_name
									, domain
									, ip_address
									, dns_host_name
									, perfmon_path
									, perfmon_drive
									, perfmon_start_time
									, perfmon_end_time
								FROM t_server s 
									INNER JOIN t_server_properties sp ON s.server_id = sp.server_id
									INNER JOIN t_perfmon_properties pp ON s.server_id = pp.server_id";
		}
	
	"DEMO"{ $DBServer 	= "status.db.stage.dexma.com"; 
			$DB 		= "statusstage";
			$SQLQuery 	= "SELECT     s.server_name
	            			FROM         dbo.t_server AS s INNER JOIN
	                        dbo.t_monitoring AS m ON s.server_id = m.server_id
	            			WHERE       (s.active = 1) AND (m.Perfmon = 1) AND (s.environment_id = 1)" 
		}
	
	"IMP" { $DBServer 	= "status.db.imp.dexma.com"; 
			$DB 		= "statusimp";
			$SQLQuery	= "SELECT     s.server_name
	            			FROM         dbo.t_server AS s INNER JOIN
	                        dbo.t_monitoring AS m ON s.server_id = m.server_id
	            			WHERE       (s.active = 1) AND (m.Perfmon = 1) AND (s.environment_id IN ('2', '9'))" 
		}
    }

## Set Parameters
$d = (get-date).toshortdatestring()
$d = $d -replace "`/","-"

$Sharename = "Operations"
$Output = $($ReturnQuery.perfmon_drive) + "\" + $Sharename + "\logs\Prodops_Scripts_Logs_$d.txt"
$title = "PerfmonCollector"
$outdir = $($ReturnQuery.perfmon_drive) + "\" + $Sharename + "\Support\Perfmon"

$ReturnQueryAll = ( Invoke-SQLCmd -query $ServerQuery -Server $DBServer -Database $DB )
#foreach ( $p IN $ReturnQueryAll ) {
#	Write-Host $($p.server_name)
#	Write-Host $($p.Domain)
#	Write-Host $($p.ip_address)
#	Write-Host $($p.dns_host_name)
#	Write-Host $($p.perfmon_path)
#	Write-Host $($p.perfmon_drive)
#	Write-Host $($p.perfmon_start_time)
#	Write-Host $($p.perfmon_end_time)
#}

$l = $ReturnQueryAll.length
$i = 0

		
		
foreach ($ReturnQuery in $ReturnQueryAll) {
     if ($ReturnQuery -ne $null) {
        $server = $($ReturnQuery.Server_Name)
        #Write-Host $server
		
		$SharePath = "\\" + $server  + "\" + $($ReturnQuery.perfmon_drive) + "$\" + $Sharename
		$DirPath = $($ReturnQuery.perfmon_drive) + ":\" + $Sharename
		#Write-Host "SharePath = " $SharePath
		#Write-Host "DirPath = " $DirPath
		#Write-Host "ShareName = " $ShareName
		
        # create share directory if it does not exist
		if (!(Test-Path -path $SharePath)) {
            New-Item $SharePath -type directory
			}
		
		# create permissions
		#$ACE = New-ACE -Name "Domain Users" -Domain "CORETECH" -Permission "Read" -Group
		#$EveryoneACE = New-Ace -ComputerName $Server -Name "Everyone" -Domain "home_office" -Permissions "Read"
		$DM_ACE = New-Ace -Name "Data Management" -Domain "home_office" -Permissions "Full" -Group #-ComputerName $Server
		$DexProNT = New-Ace -Name "DexProNT" -Domain "home_office" -Permissions "Full" #-ComputerName $Server 
		
		# create share
		#New-Share -FolderPath "C:\Temp" -ShareName "Temp" -ACEs $ACE,$ACE2  -Description "Test Description" -Computer "localhost"
		New-Share -FolderPath $DirPath -ShareName $ShareName -Computer $Server -ACEs $DexProNT
		
		$LogPath = "\\$server\" + $Sharename + "\support\perfmon\"   

		$ArchiveDir = "\\Xlog1\PerfmonLogs\$server\"
		$i++
		Write-Progress -Activity "Stopping Previous SystemHealth Data Collectors..." -Status "Completed: $i of $l Server: $Server"
		$StrCMDstop = "C:\Windows\System32\Logman.exe stop SystemHealth -s $server"
		Invoke-Expression $StrCMDstop 
		Write-Progress -Activity "Creating SystemHealth Data Collectors..." -Status "Completed: $i of $l Server: $Server"
		$StrCMDcreate = "C:\Windows\System32\Logman.exe create counter SystemHealth -s $server -cf e:\$ShareName\support\perfmon_counters.txt -si 60 -f csv -v mmddhhmm -o $outdir\$server.csv -b 00:01:00 -e 23:59:00 -y"
		Invoke-Expression $StrCMDcreate 
		Write-Progress -Activity "Starting SystemHealth Data Collectors..." -Status "Completed: $i of $l Server: $Server"
		$StrCMDstart = "C:\Windows\System32\Logman.exe start SystemHealth -s $server"       
		Invoke-Expression $StrCMDstart          
        
            #We test the path to ensure there is a log directory to begin with.
#            Write-Host $LogPath
#            if (test-path $LogPath) {
#                
#                If (test-path "ENV:PROGRAMFILES(X86)") {
#                    $ProgramDir = get-content "env:Programfiles(x86)" 
#            ## there is a bug with the $ENV: method as space before (x86) is trimmed
#                     }else {
#                    $ProgramDir = $ENV:PROGRAMFILES}
#                if (-not (test-path "$ProgramDir\7-Zip\7z.exe")) {throw "$ProgramDir\7-Zip\7z.exe needed"}
#                    set-alias sz "$ProgramDir\7-Zip\7z.exe" 
#                    foreach ($file in Get-ChildItem -path $LogPath "*.csv" | Where-Object {!($_.psiscontainer)}) {
#                        Write-Host $file
#                        if ($file.CreationTime -lt ($(Get-Date).AddDays(-1))) {
#                        #Check if directory exists, if not then create directory
#                            if (!(Test-Path -path $ArchiveDir)) {
#                                New-Item $ArchiveDir -type directory
#                                Write-Host $ArchiveDir
#                                }
#                            $name = $file.name
#                            $name = $name.trim()
#                            write-host "Source file: $name"
#                            $zipPath = "$ArchiveDir\$name.zip"
#                            $FullPath = $LogPath + $name 
# 
#                             sz a -tzip "$ZipPath" "$FullPath" | find "Everything is Ok" #7-zip prints "Everything is Ok" on success.
#                             $zipResult = $?
#                             write-host "Archive Success: $zipResult"
#                             if ($zipResult -match "True") {
#                                write-host "Archive operation successful - deleting source file: $FullPath"
#                                add-content $output "Archive operation successful - deleting source file: $FullPath"
#                                Remove-Item $FullPath #Remove source log after successful archive
#                                }else{
#                                write-host "Archive Failure - $FullPath. Local file retained"
#                                add-content $output "Archive Failure - $FullPath. Log file not deleted."
#                                     }
#                                } 
#                    }
#               }
               }
               }

