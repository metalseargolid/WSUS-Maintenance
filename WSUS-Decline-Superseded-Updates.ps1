## WSUS Superseded Update Cleanup
## This script will decline any superseded updates that are no longer needed by any computers.
<#
    .SYNTAX
     WSUS-Decline-Superseded-Updates [server] [port] [-secure] [-verbose]

    .SYNOPSIS
     Connects to WSUS and automatically declines updates that have been superseded and are not needed by any computers.
    
    .PARAMETER Server
     Optional. Name or IP of the WSUS server you are connecting to.
    
    .PARAMETER Port
     Optional. Destination port of the WSUS server you are connecting to.
    
    .PARAMETER -Secure
     Optional. Specifies that the connection to the WSUS server should be a secure connection.
    
    .PARAMETER -Verbose
     Optional. Provides additional output. This is only recommended if you are troubleshooting an issue with this Cmdlet.
    
    .EXAMPLE
     WSUS-Decline-Superseded-Updates
     This connects to WSUS at localhost on port 80, with no encryption. This is the behavior if no parameters are specified.

     WSUS-Decline-Superseded-Updates myserver.domainnane.com -Secure
     This connects to WSUS at myserver.domainname.com over port 443, as this is the default secure port.

     WSUS-Decline-Superseded-Updates myserver.domainname.tld 8531 -Secure -Verbose
     This connects to WSUS at myserver.domainname.tld on port 8531 using a secure connection, and giving additoinal output.

#>

## Cmdlet Parameters
Param([string]$server="localhost", [int]$port, [switch]$secure, [switch]$verbose)

## Set the VerbosePreference
$oldverbose = $VerbosePreference
if ($verbose) { $VerbosePreference = "continue" }

## Set the destination port
$dport = 0
if ($port -eq $null -or $port -eq 0)
{
    switch ($secure)
    {
        $True { $dport = 8531 }
        $False { $dport = 8530 }
    }
}
else { $dport = $port }

try{
    ## Load required types
    Write-Verbose "Loading required .NET types..."
    [Reflection.Assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null

    ## Connect to WSUS server
    Write-Verbose "Connecting to $($server) on port $($dport)"
    $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::getUpdateServer($server, $secure, $dport)

    ## Get list of updates to consider declining
    Write-Output "Compiling list of superseded updates that have not already been declined..."
    $updatescope = New-Object -TypeName Microsoft.UpdateServices.Administration.UpdateScope
	$updatescope.ApprovedStates = [Microsoft.UpdateServices.Administration.ApprovedStates]::HasStaleUpdateApprovals, [Microsoft.UpdateServices.Administration.ApprovedStates]::LatestRevisionApproved, [Microsoft.UpdateServices.Administration.ApprovedStates]::NotApproved
	
	$todecline = $wsus.GetUpdates($updatescope) | Where-Object { $_.IsSuperseded -eq $True }

    ## Get scope of computers that connect to WSUS
    Write-Verbose "Setting computer scope..."
    $computerscope = New-Object Microsoft.UpdateServices.Administration.ComputerTargetScope

    ## Iterate through the list and decline the superseded updates that are not needed by any computers
    ## Do not worry about accepting license agreements here, since we are only declining.
    ## This will take a long time to run if there are many updates in the $todecline list
    Write-Output "Updates that are still needed by client computers will not be declined. " `
                    "Iterating through selected updates and declining as necessary... "
    Write-Output ""

    ## Tally counts
    $declinedTotal = 0
    $neededTotal = 0
    foreach ($update in $todecline)
    {
        Write-Verbose "Name: $($update.Title)"
        Write-Verbose "Description: $($update.Description)"
        $needed = $update.GetSummary($computerscope).NotInstalledCount
        if ($needed -lt 1)
        {
            $declinedTotal++
            Write-Verbose "Action Taken: Update was declined as the update is superseded and not needed by any computers."
            $update.Decline()
        }
        else
        {
            $neededTotal++
            Write-Verbose "Action Taken: No action was taken as the update is still needed by computers connected to WSUS."
        }
        Write-Verbose ""
    }

    ## Write totals out to the console
    Write-Output "Superseded updates declined: $($declinedTotal)"
    Write-Output "Superseded updates still needed: $($neededTotal)"
} catch [System.Exception] {
    Write-Error $_
    exit -1
} finally {
    ## Change VerbosePreference back, regardless of the script's success.
    $VerbosePreference = $oldverbose
}

