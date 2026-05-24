$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$configPath = Join-Path $root 'research_digest_config.psd1'
$config = if (Test-Path -LiteralPath $configPath) {
    Import-PowerShellDataFile -LiteralPath $configPath
} else {
    @{}
}

$dashboardUrl = 'http://127.0.0.1:4173/'
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

function Stop-DashboardServer {
    Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -eq 'node.exe' -and
            $_.CommandLine -match 'web\\server\.mjs'
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
}

function Wait-ForDashboard {
    param(
        [string]$Url,
        [int]$Attempts = 20
    )

    for ($i = 0; $i -lt $Attempts; $i++) {
        Start-Sleep -Milliseconds 300
        try {
            $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2
            if ($resp.StatusCode -eq 200 -and $resp.Content -match 'assets/home\.js') {
                return $true
            }
        }
        catch {
        }
    }

    return $false
}

& (Join-Path $root 'build_dashboard_data.ps1')
& (Join-Path $root 'build_knowledge_tree.ps1')
Write-WeeklyManifest -Directory $weeklyReportDir

Stop-DashboardServer

$serverProcess = Start-Process -FilePath node -ArgumentList (Join-Path $root 'web\server.mjs') -WorkingDirectory $root -PassThru -WindowStyle Hidden

if (-not (Wait-ForDashboard -Url $dashboardUrl)) {
    Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
    throw "Dashboard failed to start at $dashboardUrl"
}

Start-Process $dashboardUrl
Write-Host "Dashboard started: $dashboardUrl"
