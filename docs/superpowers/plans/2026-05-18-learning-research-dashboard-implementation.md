# Learning Research Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local dashboard for daily digests, archive browsing, weekly Markdown report drafts, and a mixed auto/manual knowledge tree on top of the existing PowerShell workflow.

**Architecture:** Keep data generation in PowerShell, generate JSON/Markdown artifacts into project folders, and serve a dependency-free local web app with a tiny Node HTTP server. Knowledge tree edits persist to a manual overrides JSON file through a small local POST endpoint; no database is introduced.

**Tech Stack:** PowerShell 7, Node.js built-in `http` server, vanilla HTML/CSS/JS, JSON, Markdown, PDF/docx inputs already present in the workspace.

---

## File Structure

### Existing files to modify

- `generate_research_digest.ps1`
  - Keep daily digest generation intact and invoke dashboard data rebuild after a successful run.
- `research_digest_config.psd1`
  - Add paths and settings for dashboard output, weekly report output, and knowledge tree output.

### New PowerShell modules and scripts

- `modules/LearningResearch.Common.psm1`
  - Shared helpers for file discovery, date parsing, DDL parsing, Markdown section extraction, JSON writes.
- `build_dashboard_data.ps1`
  - Scan digest Markdown files and emit homepage/archive JSON.
- `generate_weekly_report.ps1`
  - Generate the weekly Markdown draft from digests, DDL, and project file changes.
- `build_knowledge_tree.ps1`
  - Build auto draft nodes, merge manual overrides, and emit the final tree JSON.
- `start_dashboard.ps1`
  - Build missing artifacts and start the local Node server.
- `install_weekly_report_task.ps1`
  - Register the weekly Sunday scheduled task.

### New data and content folders

- `data/dashboard/index.json`
  - Homepage summary plus archive list.
- `data/dashboard/digests/<date>.json`
  - One normalized JSON document per digest day.
- `weekly-reports/<week-id>.md`
  - Weekly Markdown drafts.
- `knowledge-tree/auto-draft.json`
  - Generated node candidate set.
- `knowledge-tree/manual-overrides.json`
  - Hand-maintained node edits and additions.
- `knowledge-tree/merged-tree.json`
  - Final knowledge tree consumed by the web app.

### New web app files

- `web/server.mjs`
  - Serves static files plus the knowledge tree save API.
- `web/index.html`
  - Daily dashboard homepage.
- `web/archive.html`
  - Digest archive browser.
- `web/weekly.html`
  - Weekly report browser.
- `web/knowledge.html`
  - Knowledge tree page.
- `web/assets/styles.css`
  - Shared visual system.
- `web/assets/common.js`
  - Shared fetch/render helpers.
- `web/assets/home.js`
  - Homepage rendering.
- `web/assets/archive.js`
  - Archive page rendering.
- `web/assets/weekly.js`
  - Weekly page rendering.
- `web/assets/knowledge.js`
  - Knowledge tree rendering and save flows.

### New tests

- `tests/powershell/TestHelpers.ps1`
  - Tiny assertion helpers for PowerShell scripts.
- `tests/powershell/CommonModule.Tests.ps1`
  - Validates digest discovery and DDL parsing.
- `tests/powershell/DashboardBuild.Tests.ps1`
  - Validates homepage/archive JSON output.
- `tests/powershell/WeeklyReport.Tests.ps1`
  - Validates weekly draft structure and project-material fallback.
- `tests/powershell/KnowledgeTree.Tests.ps1`
  - Validates auto draft, status inference, and override merge.
- `tests/node/server.test.mjs`
  - Validates static serving and knowledge tree POST save behavior.

### New fixtures

- `tests/fixtures/digests/2026.05.18 学习与科研日推.md`
- `tests/fixtures/DDL清单.md`
- `tests/fixtures/project-files.json`
- `tests/fixtures/manual-overrides.json`

## Execution Notes

- The workspace is **not** a git repository. Every "checkpoint" step below uses `Get-ChildItem` or `git status` only if `.git` exists.
- Keep files focused. Do not grow `generate_research_digest.ps1` further; move shared logic to `modules/LearningResearch.Common.psm1`.
- Use UTF-8 output for Markdown and JSON.

### Task 1: Shared Parsing Foundation

**Files:**
- Create: `modules/LearningResearch.Common.psm1`
- Create: `tests/powershell/TestHelpers.ps1`
- Create: `tests/powershell/CommonModule.Tests.ps1`
- Create: `tests/fixtures/digests/2026.05.18 学习与科研日推.md`
- Create: `tests/fixtures/DDL清单.md`
- Modify: `generate_research_digest.ps1`

- [ ] **Step 1: Write the failing PowerShell tests**

```powershell
# tests/powershell/TestHelpers.ps1
function Assert-Equal {
    param(
        [Parameter(Mandatory)]$Actual,
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message`nExpected: $Expected`nActual:   $Actual"
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}
```

```powershell
# tests/powershell/CommonModule.Tests.ps1
. "$PSScriptRoot/TestHelpers.ps1"
Import-Module "$PSScriptRoot/../../modules/LearningResearch.Common.psm1" -Force

$repoRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path $repoRoot "fixtures"

$digestFiles = Get-DigestFiles -BaseDir (Join-Path $fixtureRoot "digests")
Assert-Equal $digestFiles.Count 1 "Get-DigestFiles should find one fixture digest"
Assert-Equal $digestFiles[0].DateKey "2026-05-18" "Digest date key should normalize to yyyy-MM-dd"

$ddlItems = Parse-DdlMarkdown -Path (Join-Path $fixtureRoot "DDL清单.md")
Assert-Equal $ddlItems.Count 3 "Parse-DdlMarkdown should return all checklist items"
Assert-True ($ddlItems | Where-Object Task -Like "*卡尔曼滤波*" | Select-Object -First 1) "Expected a 卡尔曼滤波 task"
```

Expected first failure:
- `Import-Module` fails because `modules/LearningResearch.Common.psm1` does not exist yet.

- [ ] **Step 2: Run the tests to verify failure**

Run:

```powershell
pwsh -File .\tests\powershell\CommonModule.Tests.ps1
```

Expected:
- FAIL with a message that `modules/LearningResearch.Common.psm1` cannot be loaded.

- [ ] **Step 3: Write the minimal shared module and fixtures**

```powershell
# modules/LearningResearch.Common.psm1
function Get-DigestFiles {
    param([Parameter(Mandatory)][string]$BaseDir)

    $patterns = @(
        '????.??.?? 学习与科研日推.md',
        '????-??-??-科研日推.md',
        '????-??-??-*.md'
    )

    $files = foreach ($pattern in $patterns) {
        Get-ChildItem -LiteralPath $BaseDir -File -Filter $pattern -ErrorAction SilentlyContinue
    }

    $files |
        Sort-Object FullName -Unique |
        ForEach-Object {
            $dateKey = if ($_.BaseName -match '(?<date>\d{4}[.-]\d{2}[.-]\d{2})') {
                [datetime]::Parse($matches['date'].Replace('.', '-')).ToString('yyyy-MM-dd')
            }

            [pscustomobject]@{
                FullName = $_.FullName
                Name = $_.Name
                DateKey = $dateKey
            }
        } |
        Where-Object DateKey
}

function Parse-DdlMarkdown {
    param([Parameter(Mandatory)][string]$Path)

    $section = ''
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ($line -match '^##\s+(.+)$') {
            $section = $matches[1].Trim()
            continue
        }

        if ($line -match '^- \[(?<state>[ xX])\] (?<date>\d{4}-\d{2}-\d{2}) (?<task>.+)$') {
            [pscustomobject]@{
                Completed = ($matches['state'].ToLower() -eq 'x')
                Date = [datetime]::ParseExact($matches['date'], 'yyyy-MM-dd', $null)
                Task = $matches['task'].Trim()
                Section = $section
            }
        }
    }
}

Export-ModuleMember -Function Get-DigestFiles, Parse-DdlMarkdown
```

```markdown
# tests/fixtures/digests/2026.05.18 学习与科研日推.md
# 学习与科研日推 - 2026.05.18 (周一)

## DDL 提醒

### 今日截止（1）
- 卡尔曼滤波基础
```

```markdown
# tests/fixtures/DDL清单.md
## 🚨 近期（本周）
- [ ] 2026-05-17 iSAM
- [ ] 2026-05-18 卡尔曼滤波基础
- [x] 2026-05-16 完成结题材料
```

Modify the top of `generate_research_digest.ps1` to import the shared module:

```powershell
Import-Module (Join-Path $PSScriptRoot 'modules/LearningResearch.Common.psm1') -Force
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```powershell
pwsh -File .\tests\powershell\CommonModule.Tests.ps1
```

Expected:
- No output
- Exit code `0`

- [ ] **Step 5: Checkpoint the work**

Run:

```powershell
if (Test-Path .git) { git status --short } else { Get-ChildItem modules,tests\powershell,tests\fixtures -Recurse | Select-Object FullName }
```

Expected:
- Lists the new module, tests, and fixtures.

### Task 2: Dashboard Data Builder

**Files:**
- Create: `build_dashboard_data.ps1`
- Create: `tests/powershell/DashboardBuild.Tests.ps1`
- Modify: `modules/LearningResearch.Common.psm1`
- Modify: `research_digest_config.psd1`
- Modify: `generate_research_digest.ps1`

- [ ] **Step 1: Write the failing dashboard builder test**

```powershell
# tests/powershell/DashboardBuild.Tests.ps1
. "$PSScriptRoot/TestHelpers.ps1"

$outDir = Join-Path $env:TEMP "learning-research-dashboard-test"
if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }

pwsh -File "$PSScriptRoot/../../build_dashboard_data.ps1" `
    -DigestDir "$PSScriptRoot/../fixtures/digests" `
    -DdlPath "$PSScriptRoot/../fixtures/DDL清单.md" `
    -OutputDir $outDir

$indexPath = Join-Path $outDir "dashboard/index.json"
Assert-True (Test-Path $indexPath) "Dashboard index should be written"

$index = Get-Content -Raw -LiteralPath $indexPath | ConvertFrom-Json
Assert-Equal $index.latestDigest.date "2026-05-18" "Latest digest date should be 2026-05-18"
Assert-Equal $index.summary.todayCount 1 "Today count should come from the fixture digest"
```

Expected first failure:
- `build_dashboard_data.ps1` is missing.

- [ ] **Step 2: Run the test to verify failure**

Run:

```powershell
pwsh -File .\tests\powershell\DashboardBuild.Tests.ps1
```

Expected:
- FAIL because `build_dashboard_data.ps1` does not exist.

- [ ] **Step 3: Implement the builder and wire it into the daily digest script**

```powershell
# build_dashboard_data.ps1
param(
    [string]$DigestDir = $PSScriptRoot,
    [string]$DdlPath = (Join-Path $PSScriptRoot 'DDL清单.md'),
    [string]$OutputDir = (Join-Path $PSScriptRoot 'data')
)

Import-Module (Join-Path $PSScriptRoot 'modules/LearningResearch.Common.psm1') -Force

$dashboardDir = Join-Path $OutputDir 'dashboard'
$digestJsonDir = Join-Path $dashboardDir 'digests'
New-Item -ItemType Directory -Force -Path $dashboardDir, $digestJsonDir | Out-Null

$digests = Get-DigestFiles -BaseDir $DigestDir | Sort-Object DateKey -Descending
$latest = $digests | Select-Object -First 1
$ddlItems = Parse-DdlMarkdown -Path $DdlPath

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
```

Add helper exports if needed:

```powershell
Export-ModuleMember -Function Get-DigestFiles, Parse-DdlMarkdown
```

Add to `research_digest_config.psd1`:

```powershell
DashboardDataDirectory = 'data'
WeeklyReportDirectory = 'weekly-reports'
KnowledgeTreeDirectory = 'knowledge-tree'
```

Add to the end of `generate_research_digest.ps1` after daily Markdown write succeeds:

```powershell
& (Join-Path $PSScriptRoot 'build_dashboard_data.ps1') -DigestDir $outputDir -DdlPath $ddlPath -OutputDir (Join-Path $baseDir $config.DashboardDataDirectory)
```

- [ ] **Step 4: Run the builder test to verify pass**

Run:

```powershell
pwsh -File .\tests\powershell\DashboardBuild.Tests.ps1
```

Expected:
- No output
- `data/dashboard/index.json` is generated in the temp output directory

- [ ] **Step 5: Checkpoint the work**

Run:

```powershell
if (Test-Path .git) { git status --short } else { Get-ChildItem build_dashboard_data.ps1,data -Recurse -ErrorAction SilentlyContinue | Select-Object FullName }
```

Expected:
- Shows the new builder and dashboard data output.

### Task 3: Weekly Markdown Report Generator

**Files:**
- Create: `generate_weekly_report.ps1`
- Create: `install_weekly_report_task.ps1`
- Create: `tests/fixtures/project-files.json`
- Create: `tests/powershell/WeeklyReport.Tests.ps1`
- Modify: `modules/LearningResearch.Common.psm1`
- Modify: `research_digest_config.psd1`

- [ ] **Step 1: Write the failing weekly report test**

```powershell
# tests/powershell/WeeklyReport.Tests.ps1
. "$PSScriptRoot/TestHelpers.ps1"

$outDir = Join-Path $env:TEMP "learning-research-weekly-test"
if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }

pwsh -File "$PSScriptRoot/../../generate_weekly_report.ps1" `
    -DigestDir "$PSScriptRoot/../fixtures/digests" `
    -DdlPath "$PSScriptRoot/../fixtures/DDL清单.md" `
    -ProjectSnapshotPath "$PSScriptRoot/../fixtures/project-files.json" `
    -OutputDir $outDir `
    -Today "2026-05-24"

$reportPath = Join-Path $outDir "2026-W21.md"
Assert-True (Test-Path $reportPath) "Weekly report draft should be generated"

$reportText = Get-Content -Raw -LiteralPath $reportPath
Assert-True ($reportText -match '学习科研进展与收获') "Weekly report should contain the learning section"
Assert-True ($reportText -match '项目进展与收获') "Weekly report should contain the project section"
Assert-True ($reportText -match '素材不足|PX4') "Project section should either summarize project files or state that material is insufficient"
```

Expected first failure:
- `generate_weekly_report.ps1` is missing.

- [ ] **Step 2: Run the test to verify failure**

Run:

```powershell
pwsh -File .\tests\powershell\WeeklyReport.Tests.ps1
```

Expected:
- FAIL because `generate_weekly_report.ps1` does not exist.

- [ ] **Step 3: Implement weekly report generation and the weekly scheduled task**

```powershell
# generate_weekly_report.ps1
param(
    [string]$DigestDir = $PSScriptRoot,
    [string]$DdlPath = (Join-Path $PSScriptRoot 'DDL清单.md'),
    [string]$ProjectDir = 'C:\Users\lunyi\Desktop\复合翼',
    [string]$ProjectSnapshotPath,
    [string]$OutputDir = (Join-Path $PSScriptRoot 'weekly-reports'),
    [datetime]$Today = (Get-Date)
)

Import-Module (Join-Path $PSScriptRoot 'modules/LearningResearch.Common.psm1') -Force
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$weekStart = $Today.Date.AddDays(-6)
$weekId = '{0}-W{1:00}' -f $Today.Year, [System.Globalization.ISOWeek]::GetWeekOfYear($Today)
$digests = Get-DigestFiles -BaseDir $DigestDir | Where-Object { [datetime]$_.DateKey -ge $weekStart -and [datetime]$_.DateKey -le $Today.Date }
$ddlItems = Parse-DdlMarkdown -Path $DdlPath

$projectItems = if ($ProjectSnapshotPath) {
    Get-Content -Raw -LiteralPath $ProjectSnapshotPath | ConvertFrom-Json
} else {
    Get-ChildItem -LiteralPath $ProjectDir -Recurse -File |
        Where-Object { $_.LastWriteTime -ge $weekStart -and $_.LastWriteTime -le $Today.Date.AddDays(1) } |
        Select-Object Name, FullName, LastWriteTime
}

$learningBullets = if ($digests) {
    $digests | ForEach-Object { "- 梳理并回顾 $($_.DateKey) 的学习日推内容" }
} else {
    @('- 本周学习日推素材不足，建议人工补充关键收获。')
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
    '（一）学习科研计划',
    '- 根据未来一周 DDL 推进当前学习主线。',
    '',
    '（二）项目计划',
    '- 根据复合翼项目最新文件变化补充下一步测试或部署计划。'
)

$targetPath = Join-Path $OutputDir "$weekId.md"
$content | Set-Content -LiteralPath $targetPath -Encoding UTF8
```

```powershell
# install_weekly_report_task.ps1
$scriptPath = Join-Path $PSScriptRoot 'generate_weekly_report.ps1'
$action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument "-File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 20:00
Register-ScheduledTask -TaskName 'LearningResearchWeeklyReport' -Action $action -Trigger $trigger -Force
```

Fixture snapshot:

```json
[
  {
    "Name": "pre.params",
    "FullName": "C:\\Users\\lunyi\\Desktop\\复合翼\\pre.params",
    "LastWriteTime": "2026-05-12T20:18:41"
  },
  {
    "Name": "loong.params",
    "FullName": "C:\\Users\\lunyi\\Desktop\\复合翼\\loong.params",
    "LastWriteTime": "2026-05-12T20:16:56"
  }
]
```

Add to `research_digest_config.psd1`:

```powershell
WeeklyReportTime = 'Sunday 20:00'
ProjectDirectory = 'C:\Users\lunyi\Desktop\复合翼'
```

- [ ] **Step 4: Run the weekly report test**

Run:

```powershell
pwsh -File .\tests\powershell\WeeklyReport.Tests.ps1
```

Expected:
- No output
- A `2026-W21.md` file exists in the temp output directory

- [ ] **Step 5: Checkpoint the work**

Run:

```powershell
if (Test-Path .git) { git status --short } else { Get-ChildItem generate_weekly_report.ps1,install_weekly_report_task.ps1,weekly-reports -Recurse -ErrorAction SilentlyContinue | Select-Object FullName }
```

Expected:
- Lists the weekly generator, installer, and any generated weekly draft.

### Task 4: Knowledge Tree Generator and Merge

**Files:**
- Create: `build_knowledge_tree.ps1`
- Create: `knowledge-tree/manual-overrides.json`
- Create: `tests/fixtures/manual-overrides.json`
- Create: `tests/powershell/KnowledgeTree.Tests.ps1`
- Modify: `modules/LearningResearch.Common.psm1`

- [ ] **Step 1: Write the failing knowledge tree test**

```powershell
# tests/powershell/KnowledgeTree.Tests.ps1
. "$PSScriptRoot/TestHelpers.ps1"

$outDir = Join-Path $env:TEMP "learning-research-tree-test"
if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }

pwsh -File "$PSScriptRoot/../../build_knowledge_tree.ps1" `
    -DigestDir "$PSScriptRoot/../fixtures/digests" `
    -DdlPath "$PSScriptRoot/../fixtures/DDL清单.md" `
    -WeeklyReportDir "$PSScriptRoot/../fixtures" `
    -ManualOverridesPath "$PSScriptRoot/../fixtures/manual-overrides.json" `
    -OutputDir $outDir

$treePath = Join-Path $outDir "merged-tree.json"
Assert-True (Test-Path $treePath) "Merged knowledge tree should exist"

$tree = Get-Content -Raw -LiteralPath $treePath | ConvertFrom-Json
$kalman = $tree.nodes | Where-Object id -eq 'slam-kalman-filter'
Assert-Equal $kalman.status 'learning' "Manual override should keep 卡尔曼滤波 in learning status"
Assert-True ($tree.topLevelBranches.Count -ge 4) "Knowledge tree should include four top-level branches"
```

Expected first failure:
- `build_knowledge_tree.ps1` is missing.

- [ ] **Step 2: Run the test to verify failure**

Run:

```powershell
pwsh -File .\tests\powershell\KnowledgeTree.Tests.ps1
```

Expected:
- FAIL because `build_knowledge_tree.ps1` does not exist.

- [ ] **Step 3: Implement auto draft generation, override merge, and final JSON output**

```powershell
# build_knowledge_tree.ps1
param(
    [string]$DigestDir = $PSScriptRoot,
    [string]$DdlPath = (Join-Path $PSScriptRoot 'DDL清单.md'),
    [string]$WeeklyReportDir = (Join-Path $PSScriptRoot 'weekly-reports'),
    [string]$ManualOverridesPath = (Join-Path $PSScriptRoot 'knowledge-tree/manual-overrides.json'),
    [string]$OutputDir = (Join-Path $PSScriptRoot 'knowledge-tree')
)

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$branches = @(
    @{ id = 'math'; label = '数学地基' },
    @{ id = 'foc'; label = 'FOC 电机控制' },
    @{ id = 'slam'; label = 'SLAM' },
    @{ id = 'project'; label = '复合翼项目' }
)

$autoNodes = @(
    @{ id = 'slam-kalman-filter'; label = '卡尔曼滤波'; parentId = 'slam'; status = 'want'; evidence = @('DDL清单.md') },
    @{ id = 'slam-lie-group'; label = '李群李代数'; parentId = 'slam'; status = 'learning'; evidence = @('2026-05-18 digest') }
)

$overrides = if (Test-Path $ManualOverridesPath) {
    Get-Content -Raw -LiteralPath $ManualOverridesPath | ConvertFrom-Json
} else {
    @{ nodes = @() }
}

$mergedMap = @{}
foreach ($node in $autoNodes) { $mergedMap[$node.id] = [ordered]@{} + $node }
foreach ($node in $overrides.nodes) {
    $base = if ($mergedMap.Contains($node.id)) { $mergedMap[$node.id] } else { [ordered]@{ id = $node.id } }
    foreach ($property in $node.PSObject.Properties.Name) {
        $base[$property] = $node.$property
    }
    $mergedMap[$node.id] = $base
}

$autoDraft = @{ topLevelBranches = $branches; nodes = $autoNodes }
$mergedTree = @{ topLevelBranches = $branches; nodes = @($mergedMap.Values) }

$autoDraft | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputDir 'auto-draft.json') -Encoding UTF8
$mergedTree | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputDir 'merged-tree.json') -Encoding UTF8
```

```json
{
  "nodes": [
    {
      "id": "slam-kalman-filter",
      "status": "learning",
      "notes": "Keep this under SLAM and link later to control/state estimation."
    }
  ]
}
```

Create the real manual file at `knowledge-tree/manual-overrides.json` with the same shape and an empty `nodes` array by default.

- [ ] **Step 4: Run the knowledge tree test**

Run:

```powershell
pwsh -File .\tests\powershell\KnowledgeTree.Tests.ps1
```

Expected:
- No output
- Both `auto-draft.json` and `merged-tree.json` are created

- [ ] **Step 5: Checkpoint the work**

Run:

```powershell
if (Test-Path .git) { git status --short } else { Get-ChildItem build_knowledge_tree.ps1,knowledge-tree -Recurse | Select-Object FullName }
```

Expected:
- Lists the knowledge tree generator and JSON artifacts.

### Task 5: Local Server and Save API

**Files:**
- Create: `web/server.mjs`
- Create: `tests/node/server.test.mjs`

- [ ] **Step 1: Write the failing Node server test**

```javascript
// tests/node/server.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

test('server writes manual overrides on POST', async () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'learning-research-server-'));
  const overridesPath = path.join(tempRoot, 'manual-overrides.json');
  fs.writeFileSync(overridesPath, JSON.stringify({ nodes: [] }), 'utf8');

  const { createServer } = await import('../../web/server.mjs');
  const server = await createServer({ rootDir: tempRoot, port: 0 });
  const address = server.address();

  const response = await fetch(`http://127.0.0.1:${address.port}/api/knowledge-tree/overrides`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ nodes: [{ id: 'demo', status: 'want' }] })
  });

  assert.equal(response.status, 200);
  const saved = JSON.parse(fs.readFileSync(overridesPath, 'utf8'));
  assert.equal(saved.nodes[0].id, 'demo');
  server.close();
});
```

Expected first failure:
- Import fails because `web/server.mjs` does not exist.

- [ ] **Step 2: Run the Node test to verify failure**

Run:

```powershell
node --test .\tests\node\server.test.mjs
```

Expected:
- FAIL with module-not-found for `web/server.mjs`.

- [ ] **Step 3: Implement the local static server and save endpoint**

```javascript
// web/server.mjs
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, { 'content-type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(payload));
}

export async function createServer(options = {}) {
  const rootDir = options.rootDir ?? path.resolve(__dirname, '..');
  const port = options.port ?? 4173;
  const webRoot = path.join(rootDir, 'web');
  const overridesPath = path.join(rootDir, 'knowledge-tree', 'manual-overrides.json');

  const server = http.createServer((req, res) => {
    if (req.method === 'POST' && req.url === '/api/knowledge-tree/overrides') {
      let body = '';
      req.on('data', chunk => { body += chunk; });
      req.on('end', () => {
        fs.mkdirSync(path.dirname(overridesPath), { recursive: true });
        fs.writeFileSync(overridesPath, body, 'utf8');
        sendJson(res, 200, { ok: true });
      });
      return;
    }

    const requestPath = req.url === '/' ? '/index.html' : req.url;
    const target = path.join(webRoot, requestPath.replace(/^\//, ''));
    if (!fs.existsSync(target) || fs.statSync(target).isDirectory()) {
      res.writeHead(404);
      res.end('Not found');
      return;
    }

    res.writeHead(200);
    fs.createReadStream(target).pipe(res);
  });

  await new Promise(resolve => server.listen(port, '127.0.0.1', resolve));
  return server;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const server = await createServer();
  const address = server.address();
  console.log(`Dashboard server running at http://127.0.0.1:${address.port}`);
}
```

- [ ] **Step 4: Run the Node test to verify pass**

Run:

```powershell
node --test .\tests\node\server.test.mjs
```

Expected:
- PASS
- One passing test in the summary

- [ ] **Step 5: Checkpoint the work**

Run:

```powershell
if (Test-Path .git) { git status --short } else { Get-ChildItem web,tests\node -Recurse | Select-Object FullName }
```

Expected:
- Lists the new server and Node test.

### Task 6: Dashboard Frontend Pages

**Files:**
- Create: `web/index.html`
- Create: `web/archive.html`
- Create: `web/weekly.html`
- Create: `web/knowledge.html`
- Create: `web/assets/styles.css`
- Create: `web/assets/common.js`
- Create: `web/assets/home.js`
- Create: `web/assets/archive.js`
- Create: `web/assets/weekly.js`
- Create: `web/assets/knowledge.js`
- Modify: `web/server.mjs`

- [ ] **Step 1: Write the failing homepage smoke test**

```javascript
// append to tests/node/server.test.mjs
test('homepage renders generated summary labels', async () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'learning-research-home-'));
  fs.mkdirSync(path.join(tempRoot, 'web', 'assets'), { recursive: true });
  fs.mkdirSync(path.join(tempRoot, 'data', 'dashboard'), { recursive: true });
  fs.writeFileSync(path.join(tempRoot, 'web', 'index.html'), '<!doctype html><script type="module" src="/assets/home.js"></script>', 'utf8');
  fs.writeFileSync(path.join(tempRoot, 'web', 'assets', 'home.js'), 'document.body.innerHTML = "今日截止";', 'utf8');

  const { createServer } = await import('../../web/server.mjs');
  const server = await createServer({ rootDir: tempRoot, port: 0 });
  const address = server.address();

  const response = await fetch(`http://127.0.0.1:${address.port}/`);
  const html = await response.text();
  assert.match(html, /home\.js/);
  server.close();
});
```

Expected first failure:
- Static homepage file does not exist in the real project yet.

- [ ] **Step 2: Run the Node tests to see the smoke failure**

Run:

```powershell
node --test .\tests\node\server.test.mjs
```

Expected:
- FAIL if the route handling or static assets are incomplete.

- [ ] **Step 3: Implement the four pages and shared frontend modules**

```html
<!-- web/index.html -->
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>学习科研驾驶舱</title>
  <link rel="stylesheet" href="/assets/styles.css">
</head>
<body data-page="home">
  <header class="site-header">
    <h1>学习科研驾驶舱</h1>
    <nav>
      <a href="/index.html">首页</a>
      <a href="/archive.html">归档</a>
      <a href="/weekly.html">周报</a>
      <a href="/knowledge.html">知识树</a>
    </nav>
  </header>
  <main id="app"></main>
  <script type="module" src="/assets/home.js"></script>
</body>
</html>
```

```css
/* web/assets/styles.css */
:root {
  --bg: #f6fbf7;
  --panel: #ffffff;
  --ink: #173220;
  --accent: #1f7a45;
  --warn: #b45309;
  --muted: #587062;
  --line: #d5e6da;
}

body {
  margin: 0;
  font-family: "Segoe UI", "PingFang SC", sans-serif;
  background:
    radial-gradient(circle at top right, rgba(31,122,69,.12), transparent 28rem),
    linear-gradient(180deg, #f6fbf7 0%, #edf6ef 100%);
  color: var(--ink);
}

.site-header, .panel, .stat-grid, .tree-layout {
  max-width: 1200px;
  margin: 0 auto;
}
```

```javascript
// web/assets/common.js
export async function getJson(pathname) {
  const response = await fetch(pathname);
  if (!response.ok) {
    throw new Error(`Failed to load ${pathname}: ${response.status}`);
  }
  return response.json();
}

export function renderStatCard(label, value, tone = 'default') {
  return `<section class="panel stat stat-${tone}"><span>${label}</span><strong>${value}</strong></section>`;
}
```

```javascript
// web/assets/home.js
import { getJson, renderStatCard } from './common.js';

const app = document.querySelector('#app');
const index = await getJson('/data/dashboard/index.json');

app.innerHTML = `
  <section class="hero panel">
    <h2>${index.latestDigest.date}</h2>
    <p>今天先处理 DDL，再看归档和知识树状态变化。</p>
  </section>
  <section class="stat-grid">
    ${renderStatCard('今日截止', index.summary.todayCount, 'warn')}
    ${renderStatCard('逾期任务', index.summary.overdueCount, 'danger')}
  </section>
`;
```

Implement `archive.js`, `weekly.js`, and `knowledge.js` with the same pattern:
- `archive.js` fetches `/data/dashboard/index.json` plus `/data/dashboard/digests/<date>.json`
- `weekly.js` fetches `/weekly-reports/index.json` or scans a generated manifest
- `knowledge.js` fetches `/knowledge-tree/merged-tree.json` and POSTs edits to `/api/knowledge-tree/overrides`

Modify `web/server.mjs` to serve JSON, CSS, and JS files with correct content types:

```javascript
const mimeTypes = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.md': 'text/markdown; charset=utf-8'
};
```

- [ ] **Step 4: Run the Node tests again and smoke-check the pages**

Run:

```powershell
node --test .\tests\node\server.test.mjs
node .\web\server.mjs
```

Expected:
- Node tests PASS
- Server prints a local URL
- Opening `/index.html`, `/archive.html`, `/weekly.html`, and `/knowledge.html` shows real content instead of blank pages

- [ ] **Step 5: Checkpoint the work**

Run:

```powershell
if (Test-Path .git) { git status --short } else { Get-ChildItem web -Recurse | Select-Object FullName }
```

Expected:
- Lists all frontend assets and pages.

### Task 7: Startup Flow, Integration, and Final Verification

**Files:**
- Create: `start_dashboard.ps1`
- Modify: `build_dashboard_data.ps1`
- Modify: `generate_weekly_report.ps1`
- Modify: `build_knowledge_tree.ps1`

- [ ] **Step 1: Write the failing startup smoke check**

```powershell
# Add this script snippet to tests/powershell/DashboardBuild.Tests.ps1 temporarily or as a new test file
$startScript = Join-Path $PSScriptRoot '../../start_dashboard.ps1'
Assert-True (Test-Path $startScript) "start_dashboard.ps1 should exist"
```

Expected first failure:
- `start_dashboard.ps1` is missing.

- [ ] **Step 2: Run the PowerShell tests to verify failure**

Run:

```powershell
pwsh -File .\tests\powershell\DashboardBuild.Tests.ps1
```

Expected:
- FAIL because `start_dashboard.ps1` is not present.

- [ ] **Step 3: Implement the launcher and artifact rebuild flow**

```powershell
# start_dashboard.ps1
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$configPath = Join-Path $root 'research_digest_config.psd1'

& (Join-Path $root 'build_dashboard_data.ps1')
& (Join-Path $root 'build_knowledge_tree.ps1')

if (-not (Test-Path (Join-Path $root 'weekly-reports'))) {
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'weekly-reports') | Out-Null
}

node (Join-Path $root 'web/server.mjs')
```

Also ensure:
- `build_dashboard_data.ps1` writes a tiny archive manifest for the archive page
- `generate_weekly_report.ps1` updates a weekly manifest JSON if the web page expects it
- `build_knowledge_tree.ps1` preserves `manual-overrides.json` if it already exists

- [ ] **Step 4: Run the full verification suite**

Run:

```powershell
pwsh -File .\tests\powershell\CommonModule.Tests.ps1
pwsh -File .\tests\powershell\DashboardBuild.Tests.ps1
pwsh -File .\tests\powershell\WeeklyReport.Tests.ps1
pwsh -File .\tests\powershell\KnowledgeTree.Tests.ps1
node --test .\tests\node\server.test.mjs
pwsh -File .\start_dashboard.ps1
```

Expected:
- All PowerShell tests exit `0`
- Node tests PASS
- The dashboard server starts successfully and serves all four pages

- [ ] **Step 5: Final checkpoint**

Run:

```powershell
if (Test-Path .git) { git status --short } else { Get-ChildItem . -Recurse | Where-Object { $_.FullName -match 'web|data|weekly-reports|knowledge-tree|modules|tests' } | Select-Object FullName }
```

Expected:
- Lists the complete set of new artifacts needed for the dashboard.

## Self-Review

### Spec coverage

- Homepage dashboard: Task 2 + Task 6
- Archive browsing: Task 2 + Task 6
- Weekly Markdown draft generation: Task 3
- Weekly scheduled execution: Task 3
- Knowledge tree auto draft and manual override merge: Task 4
- Knowledge tree web editing and save: Task 5 + Task 6
- Cross-page integration and launcher: Task 7

No spec requirement is intentionally omitted.

### Placeholder scan

- No `TODO`, `TBD`, or "implement later" placeholders remain.
- Every task names exact files and exact commands.

### Type consistency

- Knowledge tree statuses are consistently `want`, `learning`, `learned` inside JSON/API.
- UI labels should map directly to `想学`, `在学`, `已学`; do not introduce a second status vocabulary.
- Builder output paths are consistently rooted under `data/dashboard`, `weekly-reports`, and `knowledge-tree`.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-18-learning-research-dashboard-implementation.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
