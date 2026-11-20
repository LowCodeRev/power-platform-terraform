# Minimal Dataverse Web API client shared by the schema deployment and the scan. Tokens come from the current
# Azure CLI session. Runs on Windows PowerShell 5.1 and PowerShell 7.

Set-StrictMode -Version Latest

$script:DvUrl = $null
$script:DvToken = $null

function Connect-Dataverse {
    param([Parameter(Mandatory)] [string] $Url)
    $script:DvUrl = $Url.TrimEnd('/')
    $script:DvToken = az account get-access-token --resource $script:DvUrl --query accessToken -o tsv
    if ($LASTEXITCODE -ne 0 -or -not $script:DvToken) { throw "Could not get a token for $script:DvUrl." }
}

function Get-DvErrorBody($ErrorRecord) {
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) { return $ErrorRecord.ErrorDetails.Message }
    try {
        $stream = $ErrorRecord.Exception.Response.GetResponseStream()
        $stream.Position = 0
        return (New-Object System.IO.StreamReader($stream)).ReadToEnd()
    }
    catch { return $ErrorRecord.Exception.Message }
}

function Invoke-Dv {
    <#
    .SYNOPSIS
    Calls {url}/api/data/v9.2/{Path}. Returns the parsed body, or with -ReturnId the GUID of the created row.
    Retries metadata-lock and throttling errors.
    #>
    param(
        [Parameter(Mandatory)] [string] $Method,
        [Parameter(Mandatory)] [string] $Path,
        $Body,
        [hashtable] $Headers = @{},
        [switch] $ReturnId
    )
    if (-not $script:DvUrl) { throw 'Call Connect-Dataverse first.' }
    $all = @{
        Authorization      = "Bearer $script:DvToken"
        Accept             = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
    }
    foreach ($k in $Headers.Keys) { $all[$k] = $Headers[$k] }
    $params = @{ Method = $Method; Uri = "$script:DvUrl/api/data/v9.2/$Path"; Headers = $all; UseBasicParsing = $true }
    if ($null -ne $Body) {
        $json = $Body
        if ($Body -isnot [string]) { $json = $Body | ConvertTo-Json -Depth 20 -Compress }
        $params.Body = [System.Text.Encoding]::UTF8.GetBytes($json)
        $params.ContentType = 'application/json; charset=utf-8'
    }
    for ($attempt = 1; ; $attempt++) {
        try {
            $response = Invoke-WebRequest @params
            if ($ReturnId) {
                $loc = [string]$response.Headers['OData-EntityId']
                return $loc.Substring($loc.LastIndexOf('(') + 1).TrimEnd(')')
            }
            if ($response.Content) {
                $text = $response.Content
                if ($text -is [byte[]]) { $text = [System.Text.Encoding]::UTF8.GetString($text) }
                if ($text.Trim()) { return ($text | ConvertFrom-Json) }
            }
            return $null
        }
        catch {
            $detail = Get-DvErrorBody $_
            $transient = $detail -match '0x80040216|0x80060891|0x80072322|another customization|MetadataCache|\block\b|429|503|Too Many Requests'
            if ($transient -and $attempt -lt 6) { Start-Sleep -Seconds (8 * $attempt); continue }
            throw "Dataverse $Method $Path failed: $detail"
        }
    }
}

function Get-DvAll {
    # Follows @odata.nextLink.
    param([Parameter(Mandatory)] [string] $Path)
    $rows = New-Object System.Collections.Generic.List[object]
    $next = $Path
    while ($next) {
        $page = Invoke-Dv GET $next
        foreach ($r in @($page.value)) { if ($null -ne $r) { $rows.Add($r) } }
        $next = $null
        if ($page.PSObject.Properties['@odata.nextLink'] -and $page.'@odata.nextLink') {
            $next = ([string]$page.'@odata.nextLink').Substring("$script:DvUrl/api/data/v9.2/".Length)
        }
    }
    return $rows
}

Export-ModuleMember -Function Connect-Dataverse, Invoke-Dv, Get-DvAll
