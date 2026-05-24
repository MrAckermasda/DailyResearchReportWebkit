. "$PSScriptRoot/TestHelpers.ps1"

$outDir = Join-Path $env:TEMP "learning-research-tree-test"
$digestDir = Join-Path $env:TEMP "learning-research-tree-digests"
$weeklyReportDir = Join-Path $env:TEMP "learning-research-tree-weekly"
$defaultOverridesPath = Join-Path $env:TEMP "learning-research-tree-default-overrides.json"
$defaultOutDir = Join-Path $env:TEMP "learning-research-tree-default-output"
if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }
if (Test-Path $digestDir) { Remove-Item -Recurse -Force $digestDir }
if (Test-Path $weeklyReportDir) { Remove-Item -Recurse -Force $weeklyReportDir }
if (Test-Path $defaultOverridesPath) { Remove-Item -Force $defaultOverridesPath }
if (Test-Path $defaultOutDir) { Remove-Item -Recurse -Force $defaultOutDir }

New-Item -ItemType Directory -Path $digestDir | Out-Null
New-Item -ItemType Directory -Path $weeklyReportDir | Out-Null

pwsh -File "$PSScriptRoot/../../build_knowledge_tree.ps1" `
    -DigestDir $digestDir `
    -DdlPath "$PSScriptRoot/../fixtures/DDL清单.md" `
    -WeeklyReportDir $weeklyReportDir `
    -ManualOverridesPath "$PSScriptRoot/../fixtures/manual-overrides.json" `
    -OutputDir $outDir `
    -Today "2026-05-16"

$treePath = Join-Path $outDir "merged-tree.json"
Assert-True (Test-Path $treePath) "Merged knowledge tree should exist"
$autoDraftPath = Join-Path $outDir "auto-draft.json"
Assert-True (Test-Path $autoDraftPath) "Auto draft knowledge tree should exist"

$tree = Get-Content -Raw -LiteralPath $treePath | ConvertFrom-Json
$autoDraft = Get-Content -Raw -LiteralPath $autoDraftPath | ConvertFrom-Json
$autoKalman = $autoDraft.nodes | Where-Object id -eq 'slam-kalman-filter'
$kalman = $tree.nodes | Where-Object id -eq 'slam-kalman-filter'
$customNode = $tree.nodes | Where-Object id -eq 'project-custom-node'

Assert-Equal $autoKalman.status 'want' "Auto draft should infer 卡尔曼滤波 as want before manual override"
Assert-Equal $kalman.status 'learning' "Manual override should keep 卡尔曼滤波 in learning status"
Assert-True ($kalman.notes -match 'Keep this under SLAM') "Manual override notes should be merged"
Assert-Equal $customNode.parentId 'project' "Manual-only override node should be merged into the tree"
Assert-Equal $customNode.status 'want' "Manual-only override node should preserve its status"

$branchIds = @($tree.topLevelBranches | ForEach-Object { $_.id })
Assert-Equal $branchIds.Count 4 "Knowledge tree should include exactly four top-level branches"
Assert-True ($branchIds -contains 'math') "Knowledge tree should include math branch"
Assert-True ($branchIds -contains 'foc') "Knowledge tree should include foc branch"
Assert-True ($branchIds -contains 'slam') "Knowledge tree should include slam branch"
Assert-True ($branchIds -contains 'project') "Knowledge tree should include project branch"

pwsh -File "$PSScriptRoot/../../build_knowledge_tree.ps1" `
    -DigestDir $digestDir `
    -DdlPath "$PSScriptRoot/../fixtures/DDL清单.md" `
    -WeeklyReportDir $weeklyReportDir `
    -ManualOverridesPath $defaultOverridesPath `
    -OutputDir $defaultOutDir `
    -Today "2026-05-16"

Assert-True (Test-Path $defaultOverridesPath) "Missing manual overrides file should be created automatically"
$defaultOverrides = Get-Content -Raw -LiteralPath $defaultOverridesPath | ConvertFrom-Json
Assert-Equal $defaultOverrides.nodes.Count 0 "Default manual overrides file should start with an empty nodes array"
