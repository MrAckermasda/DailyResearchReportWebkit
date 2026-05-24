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

$manifestPath = Join-Path $outDir "index.json"
Assert-True (Test-Path $manifestPath) "Weekly report manifest should be generated"

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
Assert-True ($text -match '本周日推主线推进') "DOCX should include a digest-derived learning topic"
Assert-True ($text -match '此部分由本人结合本周实际项目推进情况补充') "DOCX should include the project placeholder"
Assert-True ($text -match '项目进展与收获') "DOCX should contain the project progress section heading"
Assert-True ($text -match '项目计划') "DOCX should contain the project plan section heading"
Assert-True ($text -match '卡尔曼滤波基础|iSAM|根据未来一周 DDL 推进当前学习主线') "DOCX should include ongoing study tasks or the default DDL-driven learning plan"

$reportIndex = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
Assert-Equal $reportIndex.reports[0].id "20260524-4573每周工作汇报-刘英伦" "Weekly DOCX manifest should include the generated report"
