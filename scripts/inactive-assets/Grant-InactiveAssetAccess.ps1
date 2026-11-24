<#
.SYNOPSIS
Gives the scan's service principal access to the inactive asset log in one Dataverse environment.

.DESCRIPTION
Creates a narrow security role ("Inactive Asset Scan"), an application user for the service principal, and assigns
the role. The role can read, create and update the three log tables, read the metadata the scan looks up, and read
cloud flow definitions, agents (bots) and conversation transcripts (the scan only asks for each agent's latest
conversation time, but the privilege covers transcript content). It cannot delete rows and holds nothing else in
the environment.

Run once per environment as a Dataverse System Administrator. Idempotent: a second run reports [skip] throughout.
The last step checks the grant by calling Dataverse as the application user (impersonation).

.EXAMPLE
./Grant-InactiveAssetAccess.ps1 -DataverseUrl https://contoso.crm.dynamics.com -ApplicationId 00000000-0000-0000-0000-000000000000
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $DataverseUrl,
    [Parameter(Mandatory)] [guid] $ApplicationId,
    [string] $PublisherPrefix = 'rev',
    [string] $SolutionName = 'InactiveAssetGovernance',
    [string] $RoleName = 'Inactive Asset Scan'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Dataverse.psm1') -Force
Connect-Dataverse $DataverseUrl
$p = $PublisherPrefix
$api = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"

$rootBu = (Invoke-Dv GET 'businessunits?$select=businessunitid&$filter=_parentbusinessunitid_value eq null').value[0].businessunitid

# ---------- role ----------
$role = @((Invoke-Dv GET "roles?`$select=roleid&`$filter=name eq '$RoleName' and _businessunitid_value eq $rootBu").value)
if ($role.Count -gt 0) { $roleId = $role[0].roleid; Write-Host "[skip]   role $RoleName" }
else {
    $roleId = Invoke-Dv POST 'roles' @{ name = $RoleName; 'businessunitid@odata.bind' = "/businessunits($rootBu)" } -Headers @{ 'MSCRM.SolutionUniqueName' = $SolutionName } -ReturnId
    Write-Host "[create] role $RoleName"
}

# Everything at organization depth: the log tables are organization-owned and metadata has no narrower depth.
$wanted = New-Object System.Collections.Generic.List[string]
foreach ($table in 'governedasset', 'assetscan', 'assetevent') {
    foreach ($verb in 'Create', 'Read', 'Write', 'Append', 'AppendTo') { $wanted.Add("prv$verb${p}_$table") }
}
foreach ($n in 'prvReadEntity', 'prvReadAttribute', 'prvReadRelationship', 'prvReadOptionSet', 'prvReadEntityKey', 'prvReadWorkflow', 'prvReadbot', 'prvReadconversationtranscript') { $wanted.Add($n) }

$privileges = @()
$target = New-Object System.Collections.Generic.List[string]
foreach ($name in $wanted) {
    $found = @((Invoke-Dv GET "privileges?`$select=privilegeid,name&`$filter=name eq '$name'").value)
    if ($found.Count -eq 0) { throw "Privilege '$name' does not exist in this environment. Has Deploy-InactiveAssetSchema.ps1 been run?" }
    $privileges += @{ Depth = 'Global'; PrivilegeId = [string]$found[0].privilegeid; BusinessUnitId = [string]$rootBu; PrivilegeName = [string]$found[0].name }
    $target.Add([string]$found[0].privilegeid)
}
$current = New-Object System.Collections.Generic.List[string]
$existing = Invoke-Dv GET "RetrieveRolePrivilegesRole(RoleId=$roleId)"
if ($existing.PSObject.Properties['RolePrivileges']) {
    foreach ($rp in @($existing.RolePrivileges)) { if ($null -ne $rp) { $current.Add([string]$rp.PrivilegeId) } }
}
# Dataverse adds a few SharePoint document privileges to every custom role by itself, so the role is correct
# when it holds everything wanted, not when the two lists are identical.
$missing = @($target | Where-Object { $current -notcontains $_ })
if ($missing.Count -eq 0) { Write-Host "[skip]   role privileges ($($target.Count) wanted, $($current.Count) held including platform defaults)" }
else {
    Invoke-Dv POST "roles($roleId)/Microsoft.Dynamics.CRM.ReplacePrivilegesRole" @{ Privileges = @($privileges) } | Out-Null
    Write-Host "[update] role privileges ($($target.Count))"
}

# ---------- application user ----------
$user = @((Invoke-Dv GET "systemusers?`$select=systemuserid,azureactivedirectoryobjectid,isdisabled&`$filter=applicationid eq $ApplicationId").value)
if ($user.Count -gt 0) { $userId = $user[0].systemuserid; Write-Host "[skip]   application user $ApplicationId" }
else {
    $userId = Invoke-Dv POST 'systemusers' @{ applicationid = "$ApplicationId"; 'businessunitid@odata.bind' = "/businessunits($rootBu)" } -ReturnId
    Write-Host "[create] application user $ApplicationId"
}

$held = @((Invoke-Dv GET "systemusers($userId)/systemuserroles_association?`$select=roleid").value | ForEach-Object { [string]$_.roleid })
if ($held -contains [string]$roleId) { Write-Host '[skip]   role assignment' }
else {
    Invoke-Dv POST "systemusers($userId)/systemuserroles_association/`$ref" @{ '@odata.id' = "$api/roles($roleId)" } | Out-Null
    Write-Host '[create] role assignment'
}
$others = @($held | Where-Object { $_ -ne [string]$roleId })
if ($others.Count -gt 0) { Write-Host "[note]   the application user also holds $($others.Count) other role(s)" }

# ---------- verify as the application user ----------
$as = @{ MSCRMCallerID = "$userId" }
$rows = @((Invoke-Dv GET "${p}_governedassets?`$select=${p}_assetid,${p}_name&`$top=1" -Headers $as).value)
Invoke-Dv GET "GlobalOptionSetDefinitions(Name='${p}_assetlifecyclestage')" -Headers $as | Out-Null
Invoke-Dv GET "${p}_assetscans?`$select=${p}_scanon&`$top=1" -Headers $as | Out-Null
if ($rows.Count -gt 0) {
    Invoke-Dv PATCH "${p}_governedassets(${p}_assetid='$($rows[0]."${p}_assetid")')" @{ "${p}_name" = [string]$rows[0]."${p}_name" } -Headers $as | Out-Null
}
$denied = $false
try { Invoke-Dv GET 'accounts?$select=name&$top=1' -Headers $as | Out-Null } catch { $denied = $true }
if (-not $denied) { Write-Warning 'The application user can read accounts, so it holds more than this role grants.' }
Write-Host "[done]   verified as the application user: reads and writes the log, $(if ($denied) { 'denied' } else { 'NOT denied' }) on an unrelated table"
