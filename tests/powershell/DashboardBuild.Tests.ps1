. "$PSScriptRoot/TestHelpers.ps1"

$outDir = Join-Path $env:TEMP "learning-research-dashboard-test"
$emptyDigestDir = Join-Path $env:TEMP "learning-research-dashboard-empty-test"
if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }
if (Test-Path $emptyDigestDir) { Remove-Item -Recurse -Force $emptyDigestDir }

$staleDir = Join-Path $outDir "dashboard/digests"
New-Item -ItemType Directory -Force -Path $staleDir | Out-Null
$stalePath = Join-Path $staleDir "stale.json"
Set-Content -LiteralPath $stalePath -Value '{"stale":true}' -Encoding UTF8

pwsh -File "$PSScriptRoot/../../build_dashboard_data.ps1" `
    -DigestDir "$PSScriptRoot/../fixtures/digests" `
    -DdlPath "$PSScriptRoot/../fixtures/DDL清单.md" `
    -OutputDir $outDir

$indexPath = Join-Path $outDir "dashboard/index.json"
Assert-True (Test-Path $indexPath) "Dashboard index should be written"
Assert-True (-not (Test-Path $stalePath)) "Stale digest JSON should be removed"

$index = Get-Content -Raw -LiteralPath $indexPath | ConvertFrom-Json
Assert-Equal $index.latestDigest.date "2026-05-18" "Latest digest date should be 2026-05-18"
Assert-Equal $index.summary.todayCount 1 "Today count should come from the fixture digest"
Assert-Equal $index.summary.overdueCount 1 "Overdue count should come from the fixture DDL"

$digestJsonPath = Join-Path $outDir "dashboard/digests/2026-05-18.json"
Assert-True (Test-Path $digestJsonPath) "Per-digest JSON should be written"
Assert-Equal $index.archive.Count 1 "Archive should contain one digest"
Assert-Equal $index.archive[0].date "2026-05-18" "Archive entry date should match the digest"

New-Item -ItemType Directory -Force -Path $emptyDigestDir | Out-Null
$emptyOutputDir = Join-Path $env:TEMP "learning-research-dashboard-empty-output"
if (Test-Path $emptyOutputDir) { Remove-Item -Recurse -Force $emptyOutputDir }

$errorLines = @()
$emptyCommandOutput = pwsh -File "$PSScriptRoot/../../build_dashboard_data.ps1" `
    -DigestDir $emptyDigestDir `
    -DdlPath "$PSScriptRoot/../fixtures/DDL清单.md" `
    -OutputDir $emptyOutputDir 2>&1
$emptyExitCode = $LASTEXITCODE
$emptyCommandOutput | ForEach-Object { $errorLines += "$_" }

$errorText = $errorLines -join "`n"
Assert-True ($emptyExitCode -ne 0) "Empty digest input should fail"
Assert-True ($errorText -match 'No digest files found under') "Empty digest input should report a clear error"

$missingDdlPath = Join-Path $env:TEMP "learning-research-dashboard-missing-ddl.md"
if (Test-Path $missingDdlPath) { Remove-Item -Force $missingDdlPath }

$missingDdlLines = @()
$missingDdlOutput = pwsh -File "$PSScriptRoot/../../build_dashboard_data.ps1" `
    -DigestDir "$PSScriptRoot/../fixtures/digests" `
    -DdlPath $missingDdlPath `
    -OutputDir $outDir 2>&1
$missingDdlExitCode = $LASTEXITCODE
$missingDdlOutput | ForEach-Object { $missingDdlLines += "$_" }

$missingDdlText = $missingDdlLines -join "`n"
Assert-True ($missingDdlExitCode -ne 0) "Missing DDL path should fail"
Assert-True ($missingDdlText -match [regex]::Escape($missingDdlPath)) "Missing DDL path error should include the missing path"
