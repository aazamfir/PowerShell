function log([System.String] $text){write-host $text;}

function logException{
    log "Logging current exception.";
    log $Error[0].Exception;
}


function mytrycatch ([System.Management.Automation.ScriptBlock] $try,
                    [System.Management.Automation.ScriptBlock] $catch,
                    [System.Management.Automation.ScriptBlock]  $finally = $({})){



# Make all errors terminating exceptions.
    $ErrorActionPreference = "Stop";

    # Set the trap
    trap [System.Exception]{
        # Log the exception.
        logException;

        # Execute the catch statement
        & $catch;

        # Execute the finally statement
        & $finally

        # There was an exception, return false
        return $false;
    }

    # Execute the scriptblock
    & $try;

    # Execute the finally statement
    & $finally

    # The following statement was hit.. so there were no errors with the scriptblock
    return $true;
}


#execute your own try catch
cls
mytrycatch {
        gi filethatdoesnotexist; #normally non-terminating
        write-host "You won't hit me."
    } {
        Write-Host "Caught the exception";
    }


# access SSIS package files
#cls

$Packages = @();
$Packages = Get-Item -Path "C:\Users\MMessano\Documents\Visual Studio 2008\Projects\Data Management\Management\BillingReport\BillingReport\*.dtsx";

foreach ($package in $Packages ) 
{
	$DTSXPackage = Get-ISPackage -path $package
	$DTSXPackage.Name
	foreach ($connection in $DTSXPackage.Connections)
	{
		$connection.Name
		$connection.ConnectionString
	}
}