param(
    [string]$DigestDir = (Join-Path $PSScriptRoot 'daily-digests'),
    [string]$DdlPath = (Join-Path $PSScriptRoot 'DDL清单.md'),
    [string]$WeeklyReportDir = (Join-Path $PSScriptRoot 'weekly-reports'),
    [string]$ManualOverridesPath = (Join-Path $PSScriptRoot 'knowledge-tree/manual-overrides.json'),
    [string]$OutputDir = (Join-Path $PSScriptRoot 'knowledge-tree'),
    [datetime]$Today = (Get-Date)
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'modules/LearningResearch.Common.psm1') -Force

function Get-BranchDefinition {
    param([string]$Text)

    switch -Regex ($Text) {
        '卡尔曼|SLAM|李群|李代数|回环|建图|相机|VO|BTC' {
            return @{ id = 'slam'; label = 'SLAM' }
        }
        'FOC|PMSM|BLDC|电机|Clark|Park|SVPWM' {
            return @{ id = 'foc'; label = 'FOC 电机控制' }
        }
        'Strang|线性代数|矩阵|SVD|PCA|特征值' {
            return @{ id = 'math'; label = '数学地基' }
        }
        '复合翼|PX4|固定翼|试飞|空速管' {
            return @{ id = 'project'; label = '复合翼项目' }
        }
        default {
            return $null
        }
    }
}

function Get-KnowledgeNodeId {
    param(
        [Parameter(Mandatory)][string]$BranchId,
        [Parameter(Mandatory)][string]$Text
    )

    switch -Regex ($Text) {
        '卡尔曼' { return 'slam-kalman-filter' }
        '李群|李代数' { return 'slam-lie-group' }
        'Strang|线性代数' { return 'math-linear-algebra' }
        'FOC|PMSM|BLDC|电机' { return 'foc-motor-control' }
        '复合翼|PX4|固定翼|试飞' { return 'project-flight-stack' }
        default {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
            $hash = [System.Security.Cryptography.MD5]::HashData($bytes)
            $suffix = ([System.BitConverter]::ToString($hash)).Replace('-', '').Substring(0, 8).ToLower()
            return "$BranchId-$suffix"
        }
    }
}

function Get-KnowledgeLabel {
    param([string]$Text)

    switch -Regex ($Text) {
        '卡尔曼' { return '卡尔曼滤波' }
        '李群|李代数' { return '李群李代数' }
        'Strang|线性代数' { return '线性代数 / Strang 主线' }
        'FOC|PMSM|BLDC|电机' { return 'FOC 电机控制基础' }
        '复合翼|PX4|固定翼|试飞' { return '复合翼项目 / 飞控与试飞' }
        default { return $Text.Trim() }
    }
}

function Merge-Status {
    param(
        [string]$Current,
        [string]$Incoming
    )

    $rank = @{
        want = 1
        learning = 2
        learned = 3
    }

    if (-not $Current) { return $Incoming }
    if ($rank[$Incoming] -gt $rank[$Current]) { return $Incoming }
    return $Current
}

function Test-ValidStatus {
    param([string]$Status)

    return $Status -in @('want', 'learning', 'learned')
}

function Add-OrUpdateNode {
    param(
        [hashtable]$NodeMap,
        [string]$SourceText,
        [string]$Status,
        [string]$Evidence
    )

    $branch = Get-BranchDefinition -Text $SourceText
    if (-not $branch) {
        return
    }

    $nodeId = Get-KnowledgeNodeId -BranchId $branch.id -Text $SourceText
    $label = Get-KnowledgeLabel -Text $SourceText

    if (-not $NodeMap.ContainsKey($nodeId)) {
        $NodeMap[$nodeId] = [ordered]@{
            id = $nodeId
            label = $label
            parentId = $branch.id
            status = $Status
            evidence = @($Evidence)
            notes = ''
        }
        return
    }

    $node = $NodeMap[$nodeId]
    $node.status = Merge-Status -Current $node.status -Incoming $Status
    if ($Evidence -and $node.evidence -notcontains $Evidence) {
        $node.evidence += $Evidence
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$branches = @(
    @{ id = 'math'; label = '数学地基' },
    @{ id = 'foc'; label = 'FOC 电机控制' },
    @{ id = 'slam'; label = 'SLAM' },
    @{ id = 'project'; label = '复合翼项目' }
)

$branchIds = @($branches | ForEach-Object { $_.id })
$nodeMap = @{}
$today = $Today.Date

$ddlItems = Parse-DdlMarkdown -Path $DdlPath
foreach ($item in $ddlItems) {
    $status = if ($item.Completed) {
        'learned'
    } elseif ($item.Date.Date -le $today) {
        'learning'
    } else {
        'want'
    }

    Add-OrUpdateNode -NodeMap $nodeMap -SourceText $item.Task -Status $status -Evidence ("DDL: {0:yyyy-MM-dd}" -f $item.Date)
}

$digestFiles = Get-DigestFiles -BaseDir $DigestDir
foreach ($digest in $digestFiles) {
    $raw = Get-Content -Raw -LiteralPath $digest.FullName -Encoding UTF8
    foreach ($keyword in @('卡尔曼', '李群', '李代数', 'Strang', '线性代数', 'FOC', 'PMSM', 'BLDC', '复合翼', 'PX4', '固定翼', '试飞')) {
        if ($raw -match [regex]::Escape($keyword)) {
            Add-OrUpdateNode -NodeMap $nodeMap -SourceText $keyword -Status 'learning' -Evidence ("Digest: {0}" -f $digest.DateKey)
        }
    }
}

if (Test-Path -LiteralPath $WeeklyReportDir) {
    Get-ChildItem -LiteralPath $WeeklyReportDir -File -Filter '*.md' -ErrorAction SilentlyContinue | ForEach-Object {
        $raw = Get-Content -Raw -LiteralPath $_.FullName -Encoding UTF8
        foreach ($keyword in @('卡尔曼', '李群', '李代数', 'Strang', '线性代数', 'FOC', 'PMSM', 'BLDC', '复合翼', 'PX4', '固定翼', '试飞')) {
            if ($raw -match [regex]::Escape($keyword)) {
                Add-OrUpdateNode -NodeMap $nodeMap -SourceText $keyword -Status 'learned' -Evidence ("Weekly: {0}" -f $_.BaseName)
            }
        }
    }
}

$autoNodes = @($nodeMap.Values)
$autoDraft = @{
    topLevelBranches = $branches
    nodes = $autoNodes
}

if (-not (Test-Path -LiteralPath $ManualOverridesPath)) {
    $manualDir = Split-Path -Parent $ManualOverridesPath
    if ($manualDir) {
        New-Item -ItemType Directory -Force -Path $manualDir | Out-Null
    }
    '{ "nodes": [] }' | Set-Content -LiteralPath $ManualOverridesPath -Encoding UTF8
}

$overrides = Get-Content -Raw -LiteralPath $ManualOverridesPath | ConvertFrom-Json
$mergedMap = @{}
foreach ($node in $autoNodes) {
    $mergedMap[$node.id] = [ordered]@{} + $node
}

foreach ($node in $overrides.nodes) {
    if (-not (Test-ValidStatus -Status $node.status)) {
        throw "Manual override node '$($node.id)' has invalid status '$($node.status)'."
    }

    $base = if ($mergedMap.Contains($node.id)) {
        $mergedMap[$node.id]
    } else {
        if (-not $node.label -or -not $node.parentId) {
            throw "Manual override node '$($node.id)' must define label and parentId when no auto node exists."
        }
        if ($branchIds -notcontains $node.parentId) {
            throw "Manual override node '$($node.id)' has unknown parentId '$($node.parentId)'."
        }
        [ordered]@{
            id = $node.id
            label = $node.label
            parentId = $node.parentId
            status = $node.status
            evidence = @()
            notes = ''
        }
    }

    foreach ($property in $node.PSObject.Properties.Name) {
        if ($property -eq 'evidence') {
            $mergedEvidence = @($base.evidence)
            foreach ($entry in @($node.evidence)) {
                if ($mergedEvidence -notcontains $entry) {
                    $mergedEvidence += $entry
                }
            }
            $base.evidence = $mergedEvidence
            continue
        }

        $base[$property] = $node.$property
    }

    if ($base.parentId -and $branchIds -notcontains $base.parentId) {
        throw "Manual override node '$($node.id)' has unknown parentId '$($base.parentId)'."
    }

    $mergedMap[$node.id] = $base
}

$mergedTree = @{
    topLevelBranches = $branches
    nodes = @($mergedMap.Values)
}

$autoDraft | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputDir 'auto-draft.json') -Encoding UTF8
$mergedTree | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputDir 'merged-tree.json') -Encoding UTF8
