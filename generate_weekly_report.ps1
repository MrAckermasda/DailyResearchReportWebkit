param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'research_digest_config.psd1'),
    [string]$DigestDir = (Join-Path $PSScriptRoot 'daily-digests'),
    [string]$DdlPath = (Join-Path $PSScriptRoot 'DDL清单.md'),
    [string]$ProjectDir,
    [string]$ProjectSnapshotPath,
    [string]$OutputDir,
    [datetime]$Today = (Get-Date)
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'modules/LearningResearch.Common.psm1') -Force

if (Test-Path -LiteralPath $ConfigPath) {
    $config = Import-PowerShellDataFile -LiteralPath $ConfigPath
}

if (-not $PSBoundParameters.ContainsKey('ProjectDir')) {
    if ($config.ProjectDirectory) {
        $ProjectDir = $config.ProjectDirectory
    } else {
        throw 'ProjectDir is required when ProjectDirectory is not configured.'
    }
}

if (-not $PSBoundParameters.ContainsKey('OutputDir')) {
    if ($config.WeeklyReportDirectory) {
        $OutputDir = Join-Path $PSScriptRoot $config.WeeklyReportDirectory
    } else {
        $OutputDir = (Join-Path $PSScriptRoot 'weekly-reports')
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$weekStart = $Today.Date.AddDays(-6)
$isoYear = [System.Globalization.ISOWeek]::GetYear($Today)
$weekId = '{0}-W{1:00}' -f $isoYear, [System.Globalization.ISOWeek]::GetWeekOfYear($Today)

$digests = Get-DigestFiles -BaseDir $DigestDir |
    Where-Object {
        $digestDate = [datetime]$_.DateKey
        $digestDate -ge $weekStart -and $digestDate -le $Today.Date
    }

$ddlItems = Parse-DdlMarkdown -Path $DdlPath

$projectItems = if ($ProjectSnapshotPath) {
    Get-Content -Raw -LiteralPath $ProjectSnapshotPath | ConvertFrom-Json
} else {
    Get-ChildItem -LiteralPath $ProjectDir -Recurse -File |
        Where-Object {
            $_.LastWriteTime -ge $weekStart -and
            $_.LastWriteTime -le $Today.Date.AddDays(1)
        } |
        Select-Object Name, FullName, LastWriteTime
}

$learningBullets = if ($digests) {
    $digests | ForEach-Object { "- 梳理并回顾 $($_.DateKey) 的学习日推内容" }
} else {
    @('- 本周学习日推素材不足，建议人工补充关键收获。')
}

$openDdlItems = $ddlItems | Where-Object { -not $_.Completed }
if ($openDdlItems.Count -gt 0) {
    $ddlSummary = ($openDdlItems | Select-Object -First 3 -ExpandProperty Task) -join '、'
    $learningBullets += "- 当前仍需推进的学习任务包括：$ddlSummary"
}

$projectBullets = if ($projectItems.Count -gt 0) {
    $projectItems | Select-Object -First 3 | ForEach-Object { "- 项目素材更新：$($_.Name)" }
} else {
    @('- 本周项目自动汇总素材不足，建议人工补充具体飞行、调参、测试或部署进展。')
}

$content = @(
    "# $weekId 周报初稿",
    '',
    '一、本周进展与收获',
    '（一）学习科研进展与收获'
) + $learningBullets + @(
    '',
    '（二）项目进展与收获'
) + $projectBullets + @(
    '',
    '二、下周计划',
    '（一）学习科研计划'
)

$upcomingTasks = $ddlItems | Where-Object {
    -not $_.Completed -and
    $_.Date -gt $Today.Date -and
    $_.Date -le $Today.Date.AddDays(7)
}

if ($upcomingTasks.Count -gt 0) {
    $content += $upcomingTasks | Select-Object -First 3 | ForEach-Object { "- 推进 $($_.Task)" }
} else {
    $content += '- 根据未来一周 DDL 推进当前学习主线。'
}

$content += @(
    '',
    '（二）项目计划',
    '- 根据复合翼项目最新文件变化补充下一步测试或部署计划。'
)

$targetPath = Join-Path $OutputDir "$weekId.md"
$content | Set-Content -LiteralPath $targetPath -Encoding UTF8

$reportFiles = Get-ChildItem -LiteralPath $OutputDir -File -Filter '*.md' -ErrorAction SilentlyContinue |
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

$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputDir 'index.json') -Encoding UTF8
