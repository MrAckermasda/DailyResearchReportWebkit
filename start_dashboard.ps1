$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$configPath = Join-Path $root 'research_digest_config.psd1'
$config = if (Test-Path -LiteralPath $configPath) {
    Import-PowerShellDataFile -LiteralPath $configPath
} else {
    @{}
}

$weeklyReportDir = if ($config.WeeklyReportDirectory) {
    Join-Path $root $config.WeeklyReportDirectory
} else {
    Join-Path $root 'weekly-reports'
}

function Write-WeeklyManifest {
    param([string]$Directory)

    New-Item -ItemType Directory -Force -Path $Directory | Out-Null

    $reportFiles = Get-ChildItem -LiteralPath $Directory -File -Filter '*.md' -ErrorAction SilentlyContinue |
        Sort-Object BaseName -Descending

    $manifest = @{
        reports = @(
            $reportFiles | ForEach-Object {
                @{
                    id = $_.BaseName
                    file = $_.Name
                }
            }
        )
    }

    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Directory 'index.json') -Encoding UTF8
}

& (Join-Path $root 'build_dashboard_data.ps1')
& (Join-Path $root 'build_knowledge_tree.ps1')
Write-WeeklyManifest -Directory $weeklyReportDir

node (Join-Path $root 'web/server.mjs')
