# 2021-02-05 - Student Groups - Dynamic Permissions Example
$p = $person | ConvertFrom-Json
$m = $manager | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$mRef = $managerAccountReference | ConvertFrom-Json
$pRef = $permissionReference | ConvertFrom-Json
$c = $configuration | ConvertFrom-Json

# Operation is a script parameter which contains the action HelloID wants to perform for this permission
# It has one of the following values: "grant", "revoke", "update"
$o = $operation | ConvertFrom-Json

if(-Not($dryRun -eq $True)) {
    # Operation is empty for preview (dry run) mode, that's why we set it here.
    $o = "grant"
}

$success = $False
$auditLogs = New-Object Collections.Generic.List[PSCustomObject]
$dynamicPermissions = New-Object Collections.Generic.List[PSCustomObject]

$currentPermissions = @{}
foreach($permission in $pRef.CurrentPermissions) {
    $currentPermissions[$permission.Reference.Id] = $permission.DisplayName
}

$desiredPermissions = @{};
foreach($contract in $p.Contracts) {
    if($contract.Context.InConditions)
    {
        # <GradYear>.Students.<Location>
        $group_sAMAccountName = "{0}.Students.{1}" -f $p.custom.GradYear,$contract.Department.ExternalID
        $desiredPermissions[$group_sAMAccountName] = $group_sAMAccountName

        # Students.<Location>
        $group_sAMAccountName = "Students.{0}" -f $contract.Department.ExternalID
        $desiredPermissions[$group_sAMAccountName] = $group_sAMAccountName

        # Students.<Alt Location>
        if(-Not [string]::IsNullOrWhiteSpace($p.custom.AltLocation))
        {
            $group_sAMAccountName = "Students.{0}" -f $p.custom.AltLocation
            $desiredPermissions[$group_sAMAccountName] = $group_sAMAccountName
        }
    }
}

# Compare desired with current permissions and grant permissions
foreach($permission in $desiredPermissions.GetEnumerator()) {
    $dynamicPermissions.Add([PSCustomObject]@{
            DisplayName = $permission.Value
            Reference = [PSCustomObject]@{ Id = $permission.Name }
    })

    if(-Not $currentPermissions.ContainsKey($permission.Name))
    {
        # Add user to Membership
        $permissionSuccess = $true
        if(-Not($dryRun -eq $True))
        {
            try
            {
                #Note:  No errors thrown if user is already a member.
                Add-ADGroupMember -Identity $permission.Name -Members @($accountReference)
            }
            catch
            {
                $permissionSuccess = $False
                $success = $False
                # Log error for further analysis.  Contact Tools4ever Support to further troubleshoot
                Write-Error ("Error Revoking Permission from Group [{0}]" -f $permission.Name)
                Write-Error $_
            }
        }

        $auditLogs.Add([PSCustomObject]@{
            Action = "GrantDynamicPermission"
            Message = "Granted membership: {0}" -f $permission.Name
            IsError = -not $permissionSuccess
        })
    }    
}

# Compare current with desired permissions and revoke permissions
$newCurrentPermissions = @{}
foreach($permission in $currentPermissions.GetEnumerator()) {    
    if(-Not $desiredPermissions.ContainsKey($permission.Name))
    {
        # Revoke Membership
        if(-Not($dryRun -eq $True))
        {
            $permissionSuccess = $True
            try
            {
                Remove-ADGroupMember -Identity $permission.Name -Members @($accountReference) -ErrorAction 'Stop'
            }
            catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]{
                Write-Information "Identity Not Found.  Continuing"
                Write-Information $_
            }
            catch
            {
                $permissionSuccess = $False
                $success = $False
                # Log error for further analysis.  Contact Tools4ever Support to further troubleshoot.
                Write-Error ("Error Revoking Permission from Group [{0}]" -f $permission.Name)
                Write-Error $_ 
            }
        }
        
        $auditLogs.Add([PSCustomObject]@{
            Action = "RevokeDynamicPermission"
            Message = "Revoked membership: {0}" -f $permission.Name
            IsError = $False
        });
    } else {
        $newCurrentPermissions[$permission.Name] = $permission.Value
    }
}

# Update current permissions
<# Updates not needed for Group Memberships.
if ($o -eq "update") {
    foreach($permission in $newCurrentPermissions.GetEnumerator()) {    
        $auditLogs.Add([PSCustomObject]@{
            Action = "UpdateDynamicPermission";
            Message = "Updated access to department share $($permission.Value)";
            IsError = $False;
        });
    }
}
#>

$success = $True;

# Send results
$result = [PSCustomObject]@{
    Success = $success
    DynamicPermissions = $dynamicPermissions
    AuditLogs = $auditLogs
};
Write-Output ($result | ConvertTo-Json -Depth 10)
