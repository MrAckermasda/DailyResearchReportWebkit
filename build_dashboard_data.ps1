param(
    [string]$DigestDir = (Join-Path $PSScriptRoot 'daily-digests'),
    [string]$DdlPath = (Join-Path $PSScriptRoot 'DDL清单.md'),
    [string]$OutputDir = (Join-Path $PSScriptRoot 'data')
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'modules/LearningResearch.Common.psm1') -Force

$dashboardDir = Join-Path $OutputDir 'dashboard'
$digestJsonDir = Join-Path $dashboardDir 'digests'
New-Item -ItemType Directory -Force -Path $dashboardDir, $digestJsonDir | Out-Null

$digests = Get-DigestFiles -BaseDir $DigestDir | Sort-Object DateKey -Descending
if (-not $digests) {
    throw "No digest files found under $DigestDir"
}

$latest = $digests | Select-Object -First 1
$ddlItems = Parse-DdlMarkdown -Path $DdlPath

Get-ChildItem -LiteralPath $digestJsonDir -File -Filter '*.json' -ErrorAction SilentlyContinue |
    Remove-Item -Force

$documents = foreach ($digest in $digests) {
    $raw = Get-Content -Raw -LiteralPath $digest.FullName -Encoding UTF8
    $document = [pscustomobject]@{
        date = $digest.DateKey
        title = $digest.Name
        rawMarkdown = $raw
    }
    $document | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $digestJsonDir "$($digest.DateKey).json") -Encoding UTF8
    $document
}

$todayCount = ($ddlItems | Where-Object { $_.Date.ToString('yyyy-MM-dd') -eq $latest.DateKey -and -not $_.Completed }).Count
$index = [pscustomobject]@{
    latestDigest = [pscustomobject]@{
        date = $latest.DateKey
        title = $latest.Name
    }
    summary = [pscustomobject]@{
        todayCount = $todayCount
        overdueCount = ($ddlItems | Where-Object { $_.Date -lt [datetime]::Parse($latest.DateKey) -and -not $_.Completed }).Count
    }
    archive = $documents | Select-Object date, title
}

$index | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $dashboardDir 'index.json') -Encoding UTF8
