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
$reportIndexPath = Join-Path $outDir "index.json"
Assert-True (Test-Path $reportIndexPath) "Weekly report manifest should be generated"

$reportText = Get-Content -Raw -LiteralPath $reportPath
Assert-True ($reportText -match '学习科研进展与收获') "Weekly report should contain the learning section"
Assert-True ($reportText -match '项目进展与收获') "Weekly report should contain the project section"
Assert-True ($reportText -match '素材不足|PX4|pre\.params|loong\.params') "Project section should either summarize project files or state that material is insufficient"
Assert-True ($reportText -match 'iSAM|卡尔曼滤波基础') "Weekly report should incorporate open DDL task names into the learning summary"

$reportIndex = Get-Content -Raw -LiteralPath $reportIndexPath | ConvertFrom-Json
Assert-Equal $reportIndex.reports[0].id "2026-W21" "Weekly report manifest should include the generated report"

$yearBoundaryOutDir = Join-Path $env:TEMP "learning-research-weekly-year-boundary"
if (Test-Path $yearBoundaryOutDir) { Remove-Item -Recurse -Force $yearBoundaryOutDir }

pwsh -File "$PSScriptRoot/../../generate_weekly_report.ps1" `
    -DigestDir "$PSScriptRoot/../fixtures/digests" `
    -DdlPath "$PSScriptRoot/../fixtures/DDL清单.md" `
    -ProjectSnapshotPath "$PSScriptRoot/../fixtures/project-files.json" `
    -OutputDir $yearBoundaryOutDir `
    -Today "2021-01-01"

$yearBoundaryReport = Join-Path $yearBoundaryOutDir "2020-W53.md"
Assert-True (Test-Path $yearBoundaryReport) "Weekly report should use ISO week year in the filename"
