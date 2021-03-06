## WSUS Autoapprove Updates
## This script will approve updates according to our pre-defined criteria

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
    if ($server -eq "localhost") { 
        ## GetUpdateServerInstance is not a static method, so create a new AdminProxy object. Not required for connecting to a remote instance.
        $wsus = (New-Object -TypeName Microsoft.UpdateServices.Administration.AdminProxy).GetUpdateServerInstance()
    }
    else { $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::getUpdateServer($server, $secure, $dport) }

    ## Get staging and unassigned groups of computers (for future reference do NOT use the "All Computers" group)
    $hqstg = $wsus.GetComputerTargetGroups() | Where-Object {$_.Name -eq "STAGEGROUP"}
    $unassigned = $wsus.GetComputerTargetGroups() | Where-Object {$_.Name -eq "Unassigned Computers"}

    ## Get enum defined to approve an install
    $install = [Microsoft.UpdateServices.Administration.UpdateApprovalAction]::Install

    ## Create the updatescope for updates already approved for the staging group. This one will be selected by the
    ## updates already allowed by the staging group.
    $updatescope1 = New-Object -TypeName Microsoft.UpdateServices.Administration.UpdateScope
    $updatescope1.ApprovedStates = [Microsoft.UpdateServices.Administration.ApprovedStates]::HasStaleUpdateApprovals, [Microsoft.UpdateServices.Administration.ApprovedStates]::LatestRevisionApproved
    $updatescope1.ApprovedComputerTargetGroups.Add($hqstg)
    
    ## Get list of updates to approve for the staging group, and approve for all other computers in the organization
    Write-Output "Compiling list of update approvals for the staging group, ignoring declined updates..."
    $approvals = $wsus.GetUpdates($updatescope1) | Where-Object { $_.GetUpdateApprovals($unassigned).Count -lt 1 }

    ## Set up tally variables
    $unassignedsuccess = 0
    $unassignedfailed = 0
    
    Write-Output "Approving 8 day or older updates from the staging approvals for all computers..."
    foreach ($app in $approvals)
    {
        ## The following loop is designed to run through only once, as there should only be one approval for each group.
        ## If there are no approvals then the loop will not be entered.
        foreach ($a in $app.GetUpdateApprovals($hqstg))
        {
            $update = $wsus.GetUpdate($a.UpdateId)
            try {
                
                ## Accept the license agreement if we need to
                if ($update.RequiresLicenseAgreementAcceptance = $True) { $update.AcceptLicenseAgreement() }

            } catch [Microsoft.UpdateServices.Administration.WsusObjectNotFoundException] {
                
                ## Determine logging later. This might occur if the agreement isn't finished downloading
                ## or is otherwise missing from the WSUS database. Most of the time it will be the former,
                ## so the update should be approved on the next pass. This is done once again below but is not
                ## commented on.
                Write-Error "Missing License Agreement. This may happen if the agreement isn't finished downloading yet."
                $unassignedfailed++
                continue
            }

            ## Compare the times and if the update has been approved for 8 days, approve it for the other computers.
            $starttime = (Get-Date)
            $endtime = $a.CreationDate
            $timespan = New-TimeSpan -start $starttime -end $endtime
            if ($timespan.Days -le -8) 
            {
                $update.Approve($install, $unassigned)
                $unassignedsuccess++
            }
            break
        }
    }

    ## Create the updatescope for all updates marked as "Not Approved"
    $updatescope2 = New-Object -TypeName Microsoft.UpdateServices.Administration.UpdateScope
    $updatescope2.ApprovedStates = [Microsoft.UpdateServices.Administration.ApprovedStates]::NotApproved

    ## Get list of unapproved (not declined) updates and approve them for the staging group
    Write-Output "Compiling list of previously unapproved updates, ignoring declined updates..."
    $unapproved = $wsus.GetUpdates($updatescope2)

    ## More tally variables
    $stagingsuccess = 0
    $stagingfailed = 0

    Write-Output "Approving previously unapproved updates for the staging group..."
    ## Approve new updates for the staging group
    foreach ($u in $unapproved)
    {
        try {
            if ($u.RequiresLicenseAgreementAcceptance -eq $True) { $u.AcceptLicenseAgreement() }
        } catch [Microsoft.UpdateServices.Administration.WsusObjectNotFoundException] {
            Write-Error "Missing License Agreement. This may happen if the agreement isn't finished downloading yet."
            $stagingfailed++
            continue
        }

        $u.Approve($install, $hqstg) | Out-Null
        $stagingsuccess++
    }

    ## Write totals out to the console
    Write-Output "Updates successfully approved for Unassigned Computers: $($unassignedsuccess)"
    Write-Output "Updates failed to be approved for Unassigned Computers: $($unassignedfailed)"
    Write-Output "Updates successfully approved for HQ_WSUSSTG: $($stagingsuccess)"
    Write-Output "Updates failed to be approved for HQ_WSUSSTG: $($stagingfailed)"
    
} catch [System.Exception] {
    Write-Error $_
    exit -1
} finally {
    ## Change VerbosePreference back, regardless of the script's success.
    $VerbosePreference = $oldverbose
}

