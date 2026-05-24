param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'research_digest_config.psd1'),
    [string]$DigestDir = (Join-Path $PSScriptRoot 'daily-digests'),
    [string]$DdlPath = (Join-Path $PSScriptRoot 'DDL清单.md'),
    [string]$ProjectDir,
    [string]$ProjectSnapshotPath,
    [string]$ChatSummaryPath,
    [string]$TemplatePath,
    [string]$OutputDir,
    [datetime]$Today = (Get-Date)
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'modules/LearningResearch.Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/WeeklyReport.Docx.psm1') -Force

function Get-UniqueOutputPath {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$BaseFileName
    )

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($BaseFileName)
    $extension = [System.IO.Path]::GetExtension($BaseFileName)
    $candidate = Join-Path $Directory $BaseFileName

    if (-not (Test-Path -LiteralPath $candidate)) {
        return $candidate
    }

    $suffixes = @('本次生成', '自动生成', '新')
    foreach ($suffix in $suffixes) {
        $candidate = Join-Path $Directory "$baseName-$suffix$extension"
        if (-not (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    $index = 2
    while ($true) {
        $candidate = Join-Path $Directory "$baseName-$index$extension"
        if (-not (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
        $index += 1
    }
}

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

if (-not $PSBoundParameters.ContainsKey('ChatSummaryPath')) {
    $defaultChatSummaryPath = Join-Path $OutputDir 'current-chat-summary.json'
    if (Test-Path -LiteralPath $defaultChatSummaryPath) {
        $ChatSummaryPath = $defaultChatSummaryPath
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$weekStart = $Today.Date.AddDays(-6)
$isoYear = [System.Globalization.ISOWeek]::GetYear($Today)
$weekId = '{0}-W{1:00}' -f $isoYear, [System.Globalization.ISOWeek]::GetWeekOfYear($Today)
$reportDateId = $Today.ToString('yyyyMMdd')
$docxFileName = "$reportDateId-4573每周工作汇报-刘英伦.docx"

$digests = Get-DigestFiles -BaseDir $DigestDir |
    Where-Object {
        $digestDate = [datetime]$_.DateKey
        $digestDate -ge $weekStart -and $digestDate -le $Today.Date
    }

$ddlItems = Parse-DdlMarkdown -Path $DdlPath

$chatTopics = if ($ChatSummaryPath -and (Test-Path -LiteralPath $ChatSummaryPath)) {
    Get-Content -Raw -LiteralPath $ChatSummaryPath | ConvertFrom-Json
} else {
    @{ topics = @() }
}

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

$digestSummaryTopic = if ($digests) {
    $digestDates = ($digests | Sort-Object DateKey | ForEach-Object { $_.DateKey }) -join '、'
    $openTaskSummary = if ($ddlItems) {
        ($ddlItems | Where-Object { -not $_.Completed } | Select-Object -First 3 -ExpandProperty Task) -join '、'
    } else {
        ''
    }

    @{
        title = '本周日推主线推进'
        detail = if ($openTaskSummary) {
            "本周结合 $digestDates 的学习与科研日推，持续围绕视觉SLAM、卡尔曼滤波及相关数学基础推进学习，并对 $openTaskSummary 等持续性任务进行了跟进与梳理。"
        } else {
            "本周结合 $digestDates 的学习与科研日推，持续围绕当前学习主线推进相关内容整理与理解。"
        }
    }
} else {
    $null
}

$learningTopicParagraphs = @()
if ($digestSummaryTopic) {
    $learningTopicParagraphs += "● $($digestSummaryTopic.title)"
    $learningTopicParagraphs += "  $($digestSummaryTopic.detail)"
}

foreach ($topic in @($chatTopics.topics)) {
    $learningTopicParagraphs += "● $($topic.title)"
    $learningTopicParagraphs += "  $($topic.detail)"
}

if ($learningTopicParagraphs.Count -eq 0) {
    $learningTopicParagraphs += '● 本周学习科研内容待补充'
    $learningTopicParagraphs += '  本周学习科研总结素材不足，建议结合日推和实际学习记录补充。'
}

$upcomingTasks = $ddlItems | Where-Object {
    -not $_.Completed -and
    $_.Date -gt $Today.Date -and
    $_.Date -le $Today.Date.AddDays(7)
}

$planParagraphs = if ($upcomingTasks.Count -gt 0) {
    $upcomingTasks | Select-Object -First 3 | ForEach-Object { "● 推进 $($_.Task)" }
} else {
    @('● 根据未来一周 DDL 推进当前学习主线。')
}

$paragraphs = @(
    "$reportDateId-4573每周工作汇报-刘英伦",
    '一、本周进展与收获',
    '（一）学习科研进展与收获'
) + $learningTopicParagraphs + @(
    '（二）项目进展与收获',
    '● 项目进展与收获：此部分由本人结合本周实际项目推进情况补充。',
    '二、下周计划',
    '（一）学习科研计划'
) + $planParagraphs + @(
    '（二）项目计划',
    '● 项目计划：此部分由本人结合项目实际安排补充。'
)

$targetDocxPath = Get-UniqueOutputPath -Directory $OutputDir -BaseFileName $docxFileName
$docxReportId = [System.IO.Path]::GetFileNameWithoutExtension($targetDocxPath)
$markdownPreviewName = "$docxReportId.md"

$markdownPreview = $paragraphs -join "`r`n"
$previewPath = Join-Path $OutputDir $markdownPreviewName
$markdownPreview | Set-Content -LiteralPath $previewPath -Encoding UTF8

$template = Get-WeeklyTemplatePath -WeeklyReportDir $OutputDir -TemplatePath $TemplatePath -ExcludePath $targetDocxPath
Write-DocxFromTemplate -TemplatePath $template -OutputPath $targetDocxPath -Paragraphs $paragraphs

$reportFiles = Get-ChildItem -LiteralPath $OutputDir -File -Filter '*.docx' -ErrorAction SilentlyContinue |
    Sort-Object BaseName -Descending

$manifest = @{
    reports = @(
        $reportFiles | ForEach-Object {
            @{
                id = $_.BaseName.Trim()
                file = $_.Name
            }
        }
    )
}

$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputDir 'index.json') -Encoding UTF8
