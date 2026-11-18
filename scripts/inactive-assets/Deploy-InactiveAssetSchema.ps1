<#
.SYNOPSIS
Creates the Dataverse schema that the inactive asset scan logs to. Idempotent: a second run only prints [skip].

.DESCRIPTION
Solution "InactiveAssetGovernance" under the publisher with the given customization prefix:

  {p}_governedasset   one row per app or flow, holding its current lifecycle state (upserted by asset id)
  {p}_assetscan       one row per scan run: when, with which periods, and the count in each stage
  {p}_assetevent      one row each time an asset moves from one stage to another

Run as a user who can customize the environment: az login --allow-no-subscriptions --tenant <tenant>

.EXAMPLE
./Deploy-InactiveAssetSchema.ps1 -DataverseUrl https://lowcoderev.crm.dynamics.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $DataverseUrl,
    [string] $PublisherPrefix = 'rev',
    [string] $SolutionName = 'InactiveAssetGovernance'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Dataverse.psm1') -Force
Connect-Dataverse $DataverseUrl

$p = $PublisherPrefix
$sol = @{ 'MSCRM.SolutionUniqueName' = $SolutionName }

function Label([string] $Text) {
    @{ '@odata.type' = 'Microsoft.Dynamics.CRM.Label'; LocalizedLabels = @(@{ '@odata.type' = 'Microsoft.Dynamics.CRM.LocalizedLabel'; Label = $Text; LanguageCode = 1033 }) }
}
function Level([string] $Value = 'None') { @{ Value = $Value; CanBeChanged = $true; ManagedPropertyLogicalName = 'canmodifyrequirementlevelsettings' } }

# ---------- publisher and solution ----------
$publisher = @((Invoke-Dv GET "publishers?`$select=publisherid,customizationoptionvalueprefix&`$filter=customizationprefix eq '$p'").value)
if ($publisher.Count -eq 0) { throw "No publisher with customization prefix '$p' in $DataverseUrl." }
$optionBase = [int]$publisher[0].customizationoptionvalueprefix * 10000

if (@((Invoke-Dv GET "solutions?`$select=solutionid&`$filter=uniquename eq '$SolutionName'").value).Count -eq 0) {
    Invoke-Dv POST 'solutions' @{ uniquename = $SolutionName; friendlyname = 'Inactive Asset Governance'; version = '1.0.0.0'; 'publisherid@odata.bind' = "/publishers($($publisher[0].publisherid))" } | Out-Null
    Write-Host "[create] solution $SolutionName"
}
else { Write-Host "[skip]   solution $SolutionName" }

# ---------- global choices ----------
$choices = [ordered]@{
    "${p}_assetlifecyclestage" = @{ Display = 'Asset Lifecycle Stage'; Options = @('Active', 'Quarantine Warning', 'Quarantine', 'Delete Warning', 'Delete', 'Exempt') }
    "${p}_assettype"           = @{ Display = 'Asset Type'; Options = @('App', 'Flow') }
}
$existingChoices = @((Invoke-Dv GET 'GlobalOptionSetDefinitions').value | ForEach-Object { $_.Name })
$choiceIds = @{}
foreach ($name in $choices.Keys) {
    if ($existingChoices -notcontains $name) {
        $options = @()
        for ($i = 0; $i -lt $choices[$name].Options.Count; $i++) { $options += @{ Value = $optionBase + $i; Label = (Label $choices[$name].Options[$i]) } }
        Invoke-Dv POST 'GlobalOptionSetDefinitions' @{ '@odata.type' = 'Microsoft.Dynamics.CRM.OptionSetMetadata'; Name = $name; DisplayName = (Label $choices[$name].Display); IsGlobal = $true; OptionSetType = 'Picklist'; Options = $options } -Headers $sol | Out-Null
        Write-Host "[create] choice $name"
    }
    else { Write-Host "[skip]   choice $name" }
    $choiceIds[$name] = (Invoke-Dv GET "GlobalOptionSetDefinitions(Name='$name')").MetadataId
}

# ---------- tables ----------
$tables = [ordered]@{
    "${p}_governedasset" = @{ Display = 'Governed Asset'; Plural = 'Governed Assets'; Description = 'An app or cloud flow tracked by the inactive asset policy, with its current lifecycle state.' }
    "${p}_assetscan"     = @{ Display = 'Asset Scan'; Plural = 'Asset Scans'; Description = 'One run of the inactive asset scan.' }
    "${p}_assetevent"    = @{ Display = 'Asset Event'; Plural = 'Asset Events'; Description = 'A change of lifecycle stage for a governed asset.' }
}
$createdTable = $false
foreach ($t in $tables.Keys) {
    $found = $true
    try { Invoke-Dv GET "EntityDefinitions(LogicalName='$t')?`$select=LogicalName" | Out-Null } catch { $found = $false }
    if ($found) { Write-Host "[skip]   table $t"; continue }
    Invoke-Dv POST 'EntityDefinitions' @{
        '@odata.type'         = 'Microsoft.Dynamics.CRM.EntityMetadata'
        SchemaName            = $t
        DisplayName           = (Label $tables[$t].Display)
        DisplayCollectionName = (Label $tables[$t].Plural)
        Description           = (Label $tables[$t].Description)
        OwnershipType         = 'OrganizationOwned'
        HasActivities         = $false
        HasNotes              = $false
        IsActivity            = $false
        PrimaryNameAttribute  = "${p}_name"
        Attributes            = @(@{ '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'; SchemaName = "${p}_name"; IsPrimaryName = $true; MaxLength = 300; FormatName = @{ Value = 'Text' }; RequiredLevel = (Level); DisplayName = (Label 'Name') })
    } -Headers $sol | Out-Null
    Write-Host "[create] table $t"
    $createdTable = $true
}
if ($createdTable) { Start-Sleep -Seconds 20 }

# ---------- columns ----------
function Col([string] $Type, [string] $Name, [string] $Display, $Extra = @{}) { @{ Type = $Type; Name = "${p}_$Name"; Display = $Display; Extra = $Extra } }
$stage = "${p}_assetlifecyclestage"
$columns = [ordered]@{
    "${p}_governedasset" = @(
        (Col 'String' 'assetid' 'Asset ID' @{ MaxLength = 100 })
        (Col 'Choice' 'assettype' 'Asset Type' @{ Choice = "${p}_assettype" })
        (Col 'String' 'subtype' 'Subtype' @{ MaxLength = 100 })
        (Col 'String' 'environmentid' 'Environment ID' @{ MaxLength = 100 })
        (Col 'String' 'environmentname' 'Environment' @{ MaxLength = 200 })
        (Col 'String' 'ownerobjectid' 'Owner Object ID' @{ MaxLength = 100 })
        (Col 'String' 'ownerupn' 'Owner UPN' @{ MaxLength = 320 })
        (Col 'String' 'ownername' 'Owner' @{ MaxLength = 200 })
        (Col 'String' 'platformstate' 'Platform State' @{ MaxLength = 100 })
        (Col 'DateTime' 'assetcreatedon' 'Asset Created On')
        (Col 'DateTime' 'lastmodifiedon' 'Last Modified On')
        (Col 'DateTime' 'lastrunon' 'Last Run On')
        (Col 'DateTime' 'lastactivityon' 'Last Activity On')
        (Col 'String' 'lastactivitysource' 'Last Activity Source' @{ MaxLength = 100 })
        (Col 'String' 'usagesignal' 'Usage Signal' @{ MaxLength = 100 })
        (Col 'Decimal' 'daysinactive' 'Days Inactive')
        (Col 'Choice' 'stage' 'Stage' @{ Choice = $stage })
        (Col 'String' 'nextstage' 'Next Stage' @{ MaxLength = 100 })
        (Col 'DateTime' 'nextstageon' 'Next Stage On')
        (Col 'DateTime' 'quarantinewarningon' 'Quarantine Warning On')
        (Col 'DateTime' 'quarantineon' 'Quarantine On')
        (Col 'DateTime' 'deletewarningon' 'Delete Warning On')
        (Col 'DateTime' 'deleteon' 'Delete On')
        (Col 'String' 'exemptreason' 'Exempt Reason' @{ MaxLength = 500 })
        (Col 'DateTime' 'firstseenon' 'First Seen On')
        (Col 'DateTime' 'lastscanon' 'Last Scan On')
    )
    "${p}_assetscan"     = @(
        (Col 'DateTime' 'scanon' 'Scan On')
        (Col 'DateTime' 'evaluatedasof' 'Evaluated As Of')
        (Col 'String' 'mode' 'Mode' @{ MaxLength = 50 })
        (Col 'Boolean' 'istest' 'Is Test')
        (Col 'Decimal' 'inactivedays' 'Inactive Days')
        (Col 'Decimal' 'quarantinewarningdays' 'Quarantine Warning Days')
        (Col 'Decimal' 'quarantineddays' 'Quarantined Days')
        (Col 'Decimal' 'deletewarningdays' 'Delete Warning Days')
        (Col 'Integer' 'totalcount' 'Total')
        (Col 'Integer' 'activecount' 'Active')
        (Col 'Integer' 'quarantinewarningcount' 'Quarantine Warning')
        (Col 'Integer' 'quarantinecount' 'Quarantine')
        (Col 'Integer' 'deletewarningcount' 'Delete Warning')
        (Col 'Integer' 'deletecount' 'Delete')
        (Col 'Integer' 'exemptcount' 'Exempt')
        (Col 'String' 'runurl' 'Run URL' @{ MaxLength = 500; Format = 'Url' })
    )
    "${p}_assetevent"    = @(
        (Col 'DateTime' 'eventon' 'Event On')
        (Col 'Choice' 'fromstage' 'From Stage' @{ Choice = $stage })
        (Col 'Choice' 'tostage' 'To Stage' @{ Choice = $stage })
        (Col 'Decimal' 'daysinactive' 'Days Inactive')
    )
}

function New-ColumnBody($c) {
    $body = @{ SchemaName = $c.Name; DisplayName = (Label $c.Display); RequiredLevel = (Level) }
    switch ($c.Type) {
        'String' {
            $format = 'Text'; if ($c.Extra.ContainsKey('Format')) { $format = $c.Extra.Format }
            $body['@odata.type'] = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'; $body.MaxLength = $c.Extra.MaxLength; $body.FormatName = @{ Value = $format }
        }
        'DateTime' { $body['@odata.type'] = 'Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'; $body.Format = 'DateAndTime'; $body.DateTimeBehavior = @{ Value = 'UserLocal' } }
        'Decimal' { $body['@odata.type'] = 'Microsoft.Dynamics.CRM.DecimalAttributeMetadata'; $body.MinValue = 0; $body.MaxValue = 1000000; $body.Precision = 2 }
        'Integer' { $body['@odata.type'] = 'Microsoft.Dynamics.CRM.IntegerAttributeMetadata'; $body.Format = 'None'; $body.MinValue = 0; $body.MaxValue = 2147483647 }
        'Choice' { $body['@odata.type'] = 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata'; $body['GlobalOptionSet@odata.bind'] = "/GlobalOptionSetDefinitions($($choiceIds[$c.Extra.Choice]))" }
        'Boolean' {
            $body['@odata.type'] = 'Microsoft.Dynamics.CRM.BooleanAttributeMetadata'; $body.DefaultValue = $false
            $body.OptionSet = @{ '@odata.type' = 'Microsoft.Dynamics.CRM.BooleanOptionSetMetadata'; TrueOption = @{ Value = 1; Label = (Label 'Yes') }; FalseOption = @{ Value = 0; Label = (Label 'No') } }
        }
    }
    return $body
}

foreach ($t in $columns.Keys) {
    $have = @((Invoke-Dv GET "EntityDefinitions(LogicalName='$t')/Attributes?`$select=LogicalName").value | ForEach-Object { $_.LogicalName })
    foreach ($c in $columns[$t]) {
        if ($have -contains $c.Name) { Write-Host "[skip]   column $t.$($c.Name)"; continue }
        Invoke-Dv POST "EntityDefinitions(LogicalName='$t')/Attributes" (New-ColumnBody $c) -Headers $sol | Out-Null
        Write-Host "[create] column $t.$($c.Name)"
        Start-Sleep -Seconds 2
    }
}

# ---------- lookups (asset event -> governed asset, asset event -> asset scan) ----------
# A table can have only one parental (cascade delete) relationship: events die with their asset, not their scan.
$lookups = @(
    @{ Name = "${p}_asset"; Display = 'Asset'; Target = "${p}_governedasset"; Relationship = "${p}_governedasset_assetevent"; Delete = 'Cascade' }
    @{ Name = "${p}_scan"; Display = 'Scan'; Target = "${p}_assetscan"; Relationship = "${p}_assetscan_assetevent"; Delete = 'RemoveLink' }
)
$have = @((Invoke-Dv GET "EntityDefinitions(LogicalName='${p}_assetevent')/Attributes?`$select=LogicalName").value | ForEach-Object { $_.LogicalName })
foreach ($l in $lookups) {
    if ($have -contains $l.Name) { Write-Host "[skip]   lookup ${p}_assetevent.$($l.Name)"; continue }
    Invoke-Dv POST 'RelationshipDefinitions' @{
        '@odata.type'        = 'Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata'
        SchemaName           = $l.Relationship
        ReferencedEntity     = $l.Target
        ReferencedAttribute  = "$($l.Target)id"
        ReferencingEntity    = "${p}_assetevent"
        CascadeConfiguration = @{ Assign = 'NoCascade'; Delete = $l.Delete; Merge = 'NoCascade'; Reparent = 'NoCascade'; Share = 'NoCascade'; Unshare = 'NoCascade' }
        Lookup               = @{ '@odata.type' = 'Microsoft.Dynamics.CRM.LookupAttributeMetadata'; SchemaName = $l.Name; DisplayName = (Label $l.Display); RequiredLevel = (Level) }
    } -Headers $sol | Out-Null
    Write-Host "[create] lookup ${p}_assetevent.$($l.Name)"
    Start-Sleep -Seconds 8
}

# ---------- alternate key: lets the scan upsert a governed asset by its platform id ----------
$keyName = "${p}_assetidkey"
$keys = @((Invoke-Dv GET "EntityDefinitions(LogicalName='${p}_governedasset')/Keys").value)
if (@($keys | Where-Object { $_.LogicalName -eq $keyName }).Count -eq 0) {
    Invoke-Dv POST "EntityDefinitions(LogicalName='${p}_governedasset')/Keys" @{ SchemaName = $keyName; DisplayName = (Label 'Asset ID'); KeyAttributes = @("${p}_assetid") } -Headers $sol | Out-Null
    Write-Host "[create] key ${p}_governedasset.$keyName"
}
else { Write-Host "[skip]   key ${p}_governedasset.$keyName" }
for ($i = 0; $i -lt 30; $i++) {
    $status = (@((Invoke-Dv GET "EntityDefinitions(LogicalName='${p}_governedasset')/Keys").value) | Where-Object { $_.LogicalName -eq $keyName }).EntityKeyIndexStatus
    if ($status -eq 'Active') { break }
    Start-Sleep -Seconds 5
}
if ($status -ne 'Active') { throw "Alternate key $keyName is '$status', expected Active." }

# ---------- publish ----------
$xml = '<importexportxml><entities>' + (($tables.Keys | ForEach-Object { "<entity>$_</entity>" }) -join '') + '</entities></importexportxml>'
Invoke-Dv POST 'PublishXml' @{ ParameterXml = $xml } | Out-Null
Write-Host '[done]   published'
