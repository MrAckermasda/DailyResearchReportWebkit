# Weekly Report DOCX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the weekly report Markdown output with a new `.docx` report generator that uses an existing weekly report as a style template and synthesizes learning content from this week’s digests plus this chat window.

**Architecture:** Keep the current PowerShell pipeline as the orchestrator, but add a small `.docx` templating path based on copying an existing report and replacing its main document body XML. The generator will build structured weekly content first, then render it into Word paragraphs using the existing report’s section layout and produce a new `.docx` file without overwriting older reports.

**Tech Stack:** PowerShell 7, Open Packaging Convention (`.docx` zip/XML), existing weekly report `.docx` files in `weekly-reports/`, existing digest Markdown files in `daily-digests/`.

---

## File Structure

### Existing files to modify

- `generate_weekly_report.ps1`
  - Convert from Markdown writer into `.docx` report generator and manifest writer.
- `research_digest_config.psd1`
  - Add docx-template and weekly report naming settings if needed.
- `tests/powershell/WeeklyReport.Tests.ps1`
  - Replace Markdown-oriented assertions with `.docx`-oriented assertions.
- `操作指南.md`
  - Update weekly report usage to reflect `.docx` generation and new manual workflow.

### New files

- `modules/WeeklyReport.Docx.psm1`
  - Focused helpers for locating a template `.docx`, extracting/replacing Word document XML, and writing a new `.docx`.
- `tests/fixtures/chat-weekly-summary.json`
  - Structured summary of the current chat window’s learning topics used by tests.
- `tests/powershell/WeeklyReport.Docx.Tests.ps1`
  - Optional focused tests for docx rendering helpers if Task 2 grows too large.

### Existing files kept as data sources

- `daily-digests/`
  - Weekly digest Markdown source.
- `weekly-reports/*.docx`
  - Existing reports used as template references.
- `DDL清单.md`
  - Source for next-week study plans.

## Execution Notes

- The workspace now has a `.git` directory, but the environment still may not have `git.exe` in PATH. Do not rely on git commands for verification.
- The current project already generates `.md` weekly reports and `index.json`; preserve or replace that behavior deliberately so the weekly page still has a valid manifest.
- Keep this plan tightly scoped to weekly report generation. Do not change homepage/archive/knowledge behavior here.

### Task 1: Add Failing DOCX-Oriented Weekly Report Test

**Files:**
- Create: `tests/fixtures/chat-weekly-summary.json`
- Modify: `tests/powershell/WeeklyReport.Tests.ps1`

- [ ] **Step 1: Write the failing test first**

Create the chat summary fixture:

```json
{
  "topics": [
    {
      "title": "视觉SLAM基础几何",
      "detail": "本周围绕归一化坐标、本质矩阵四解与正深度判别进行了系统梳理，并进一步理解了单应矩阵在平面场景和纯旋转情形下的适用条件。"
    },
    {
      "title": "单目初始化与优化推导",
      "detail": "继续推导单目相机2D-2D初始化、本质矩阵约束，以及BA优化中相机模型、SE(3)扰动和雅可比结构。"
    }
  ]
}
```

Replace `tests/powershell/WeeklyReport.Tests.ps1` with a `.docx`-oriented test:

```powershell
. "$PSScriptRoot/TestHelpers.ps1"

$outDir = Join-Path $env:TEMP "learning-research-weekly-docx-test"
if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }

pwsh -File "$PSScriptRoot/../../generate_weekly_report.ps1" `
    -DigestDir "$PSScriptRoot/../fixtures/digests" `
    -DdlPath "$PSScriptRoot/../fixtures/DDL清单.md" `
    -ProjectSnapshotPath "$PSScriptRoot/../fixtures/project-files.json" `
    -ChatSummaryPath "$PSScriptRoot/../fixtures/chat-weekly-summary.json" `
    -TemplatePath "$PSScriptRoot/../../weekly-reports/20260517-4573每周工作汇报-刘英伦 .docx" `
    -OutputDir $outDir `
    -Today "2026-05-24"

$reportPath = Join-Path $outDir "20260524-4573每周工作汇报-刘英伦.docx"
Assert-True (Test-Path $reportPath) "Weekly DOCX report should be generated"

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($reportPath)
try {
    $entry = $zip.Entries | Where-Object { $_.FullName -eq 'word/document.xml' } | Select-Object -First 1
    $reader = New-Object System.IO.StreamReader($entry.Open())
    $xml = $reader.ReadToEnd()
    $reader.Dispose()
}
finally {
    $zip.Dispose()
}

$text = $xml -replace '<w:tab[^>]*/>', "`t" -replace '</w:p>', "`n" -replace '<[^>]+>', ''
$text = [System.Net.WebUtility]::HtmlDecode($text)

Assert-True ($text -match '学习科研进展与收获') "DOCX should contain learning section"
Assert-True ($text -match '视觉SLAM基础几何') "DOCX should contain topic-style learning bullet titles"
Assert-True ($text -match '归一化坐标') "DOCX should include synthesized detail text"
Assert-True ($text -match '此部分由本人结合本周实际项目推进情况补充') "DOCX should include the project placeholder"
Assert-True ($text -match '卡尔曼滤波基础|iSAM') "DOCX should include next-week or ongoing study tasks"
```

Expected first failure:
- `generate_weekly_report.ps1` still emits `.md`, not the new `.docx`.

- [ ] **Step 2: Run the test to verify failure**

Run:

```powershell
pwsh -File .\tests\powershell\WeeklyReport.Tests.ps1
```

Expected:
- FAIL because the `.docx` file is not generated.

- [ ] **Step 3: Checkpoint**

Run:

```powershell
Get-ChildItem tests\fixtures,tests\powershell | Select-Object FullName
```

Expected:
- Lists the updated weekly test and new chat summary fixture.

### Task 2: Implement DOCX Template Rendering and Report Content Builder

**Files:**
- Create: `modules/WeeklyReport.Docx.psm1`
- Modify: `generate_weekly_report.ps1`

- [ ] **Step 1: Add the docx helper module**

Create `modules/WeeklyReport.Docx.psm1`:

```powershell
function Get-WeeklyTemplatePath {
    param(
        [Parameter(Mandatory)][string]$WeeklyReportDir,
        [string]$TemplatePath
    )

    if ($TemplatePath) {
        return (Resolve-Path -LiteralPath $TemplatePath).Path
    }

    $template = Get-ChildItem -LiteralPath $WeeklyReportDir -File -Filter '*.docx' |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $template) {
        throw "No weekly report template .docx found under $WeeklyReportDir"
    }

    return $template.FullName
}

function Convert-ToWordXmlText {
    param([Parameter(Mandatory)][string]$Text)

    $escaped = [System.Security.SecurityElement]::Escape($Text)
    return $escaped -replace "`r?`n", '</w:t><w:br/><w:t xml:space="preserve">'
}

function New-WeeklyParagraphXml {
    param(
        [Parameter(Mandatory)][string]$Text
    )

    $wordText = Convert-ToWordXmlText -Text $Text
    return "<w:p><w:r><w:t xml:space=""preserve"">$wordText</w:t></w:r></w:p>"
}

function Write-DocxFromTemplate {
    param(
        [Parameter(Mandatory)][string]$TemplatePath,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string[]]$Paragraphs
    )

    Copy-Item -LiteralPath $TemplatePath -Destination $OutputPath -Force

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::Open($OutputPath, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq 'word/document.xml' } | Select-Object -First 1
        if (-not $entry) {
            throw 'word/document.xml not found in template'
        }

        $reader = New-Object System.IO.StreamReader($entry.Open())
        $xml = $reader.ReadToEnd()
        $reader.Dispose()

        $bodyXml = ($Paragraphs | ForEach-Object { New-WeeklyParagraphXml -Text $_ }) -join ''
        $xml = [regex]::Replace($xml, '(?s)(<w:body>).*?(<w:sectPr\b.*?</w:sectPr>)', "`$1$bodyXml`$2")

        $entry.Delete()
        $newEntry = $zip.CreateEntry('word/document.xml')
        $writer = New-Object System.IO.StreamWriter($newEntry.Open())
        $writer.Write($xml)
        $writer.Dispose()
    }
    finally {
        $zip.Dispose()
    }
}

Export-ModuleMember -Function Get-WeeklyTemplatePath, Write-DocxFromTemplate
```

- [ ] **Step 2: Replace Markdown generation with DOCX generation**

Modify `generate_weekly_report.ps1` so it:

1. Imports `modules/WeeklyReport.Docx.psm1`
2. Accepts two new optional parameters:
   - `ChatSummaryPath`
   - `TemplatePath`
3. Builds topic-based learning content from:
   - digests
   - DDL
   - chat summary fixture / future real summary input
4. Emits a new `.docx`

Use this core content structure:

```powershell
$reportDateId = $Today.ToString('yyyyMMdd')
$docxFileName = "$reportDateId-4573每周工作汇报-刘英伦.docx"

$chatTopics = if ($ChatSummaryPath) {
    Get-Content -Raw -LiteralPath $ChatSummaryPath | ConvertFrom-Json
} else {
    @{ topics = @() }
}

$learningTopicParagraphs = @()
foreach ($topic in $chatTopics.topics) {
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
```

Then write with:

```powershell
$template = Get-WeeklyTemplatePath -WeeklyReportDir $OutputDir -TemplatePath $TemplatePath
$targetPath = Join-Path $OutputDir $docxFileName
Write-DocxFromTemplate -TemplatePath $template -OutputPath $targetPath -Paragraphs $paragraphs
```

Also keep writing `weekly-reports/index.json`, but make it index `.docx` files instead of `.md`.

- [ ] **Step 3: Run the weekly report test to verify pass**

Run:

```powershell
pwsh -File .\tests\powershell\WeeklyReport.Tests.ps1
```

Expected:
- PASS
- `.docx` file exists
- extracted document text contains the expected sections and topic/detail lines

- [ ] **Step 4: Checkpoint**

Run:

```powershell
Get-ChildItem modules,weekly-reports | Select-Object FullName
```

Expected:
- Lists the new docx helper module and generated report artifacts.

### Task 3: Generate This Week’s Real Weekly DOCX and Update Docs

**Files:**
- Modify: `操作指南.md`
- Modify: `research_digest_config.psd1` only if extra template settings are truly needed
- Output: `weekly-reports/<new docx>`

- [ ] **Step 1: Add an operational note to the guide**

Update `操作指南.md` so weekly report instructions say:

```text
pwsh -File .\generate_weekly_report.ps1
```

and describe that the output is now `.docx` in `weekly-reports/`.

- [ ] **Step 2: Generate the actual weekly report DOCX**

Run the generator against real project data:

```powershell
pwsh -File .\generate_weekly_report.ps1
```

Expected:
- A new `.docx` appears in `weekly-reports/`
- The previous `.docx` files remain untouched

- [ ] **Step 3: Verify the generated real report text**

Run a simple XML extraction check:

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$file = Get-ChildItem .\weekly-reports -Filter '*.docx' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$zip = [System.IO.Compression.ZipFile]::OpenRead($file.FullName)
try {
  $entry = $zip.Entries | Where-Object { $_.FullName -eq 'word/document.xml' } | Select-Object -First 1
  $reader = New-Object System.IO.StreamReader($entry.Open())
  $xml = $reader.ReadToEnd()
  $reader.Dispose()
}
finally {
  $zip.Dispose()
}
$text = $xml -replace '<w:tab[^>]*/>', "`t" -replace '</w:p>', "`n" -replace '<[^>]+>', ''
$text = [System.Net.WebUtility]::HtmlDecode($text)
$text
```

Expected:
- Contains section headings
- Contains topic-style learning bullets with paragraph detail
- Contains the project placeholder

- [ ] **Step 4: Final checkpoint**

Run:

```powershell
Get-ChildItem .\weekly-reports | Sort-Object LastWriteTime -Descending | Select-Object -First 10 Name,LastWriteTime
```

Expected:
- Shows the new `.docx` alongside older reports, with old files preserved

## Self-Review

### Spec coverage

- `.docx` output instead of Markdown: Task 2
- new file, no overwrite: Task 2 + Task 3
- style based on existing weekly report: Task 2
- learning section by topic with paragraph detail: Task 2
- current chat summary integration path: Task 1 + Task 2
- project placeholder only: Task 2
- next-week plan from DDL: Task 2

No spec requirement is intentionally omitted.

### Placeholder scan

- No `TODO` or `TBD` placeholders remain.
- Every execution step has explicit commands and expected results.

### Type consistency

- Weekly report primary output is consistently `.docx`
- Weekly manifest indexes `.docx` files
- Chat summary input is consistently JSON-based for implementation and testing

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-24-weekly-report-docx-implementation.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
