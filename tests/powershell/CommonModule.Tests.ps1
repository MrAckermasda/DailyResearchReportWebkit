. "$PSScriptRoot/TestHelpers.ps1"
Import-Module "$PSScriptRoot/../../modules/LearningResearch.Common.psm1" -Force

$repoRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path $repoRoot "fixtures"
$tempDigestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("learning-research-digest-test-" + [guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Path $tempDigestRoot | Out-Null

try {
    Copy-Item -LiteralPath (Join-Path $fixtureRoot "digests/2026.05.18 学习与科研日推.md") -Destination $tempDigestRoot
    Set-Content -LiteralPath (Join-Path $tempDigestRoot "2026-05-18-learning-research-dashboard-design.md") -Value "# note" -Encoding UTF8

    $digestFiles = Get-DigestFiles -BaseDir $tempDigestRoot
    Assert-Equal $digestFiles.Count 1 "Get-DigestFiles should find one fixture digest"
    Assert-Equal $digestFiles[0].DateKey "2026-05-18" "Digest date key should normalize to yyyy-MM-dd"

    $ddlItems = Parse-DdlMarkdown -Path (Join-Path $fixtureRoot "DDL清单.md")
    Assert-Equal $ddlItems.Count 3 "Parse-DdlMarkdown should return all checklist items"

    $incompleteItem = $ddlItems | Where-Object Completed -eq $false | Select-Object -First 1
    Assert-True ($null -ne $incompleteItem) "Expected at least one incomplete DDL item"

    $completedItem = $ddlItems | Where-Object Completed -eq $true | Select-Object -First 1
    Assert-True ($null -ne $completedItem) "Expected at least one completed DDL item"

    $kalmanTask = $ddlItems | Where-Object Task -Like "*卡尔曼滤波*" | Select-Object -First 1
    Assert-True ($null -ne $kalmanTask) "Expected a 卡尔曼滤波 task"
    Assert-Equal $kalmanTask.Section "🚨 近期（本周）" "Kalman task should retain its source section"
    Assert-Equal $kalmanTask.Date.ToString('yyyy-MM-dd') "2026-05-18" "Kalman task should parse its due date"
}
finally {
    if (Test-Path -LiteralPath $tempDigestRoot) {
        Remove-Item -LiteralPath $tempDigestRoot -Recurse -Force
    }
}
