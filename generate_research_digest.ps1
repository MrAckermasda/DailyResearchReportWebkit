param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'research_digest_config.psd1')
)

Import-Module (Join-Path $PSScriptRoot 'modules/LearningResearch.Common.psm1') -Force

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-WeekdayCn {
    param([DateTime]$Date)

    switch ($Date.DayOfWeek.value__) {
        0 { '周日' }
        1 { '周一' }
        2 { '周二' }
        3 { '周三' }
        4 { '周四' }
        5 { '周五' }
        6 { '周六' }
        default { '' }
    }
}

function Normalize-Text {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $decoded = [System.Net.WebUtility]::HtmlDecode($Text)
    $decoded = $decoded -replace '\s+', ' '
    return $decoded.Trim()
}

function Get-SectionTag {
    param(
        [string]$H2,
        [string]$H3,
        [string]$H4
    )

    $parts = @()
    foreach ($item in @($H2, $H3, $H4)) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            $clean = $item.Trim()
            $clean = $clean.Trim()
            if ($clean) {
                $parts += $clean
            }
        }
    }

    if ($parts.Count -eq 0) {
        return '未分类'
    }

    return ($parts -join ' / ')
}

function Parse-DdlTasks {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "DDL file not found: $Path"
    }

    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    $h2 = ''
    $h3 = ''
    $h4 = ''
    $tasks = @()

    foreach ($line in $lines) {
        if ($line -match '^##\s+(.+)$') {
            $h2 = $matches[1]
            $h3 = ''
            $h4 = ''
            continue
        }
        if ($line -match '^###\s+(.+)$') {
            $h3 = $matches[1]
            $h4 = ''
            continue
        }
        if ($line -match '^####\s+(.+)$') {
            $h4 = $matches[1]
            continue
        }
        if ($line -match '^- \[(?<state>[ xX])\] (?<date>\d{4}-\d{2}-\d{2}) (?<task>.+)$') {
            $dateValue = [DateTime]::ParseExact($matches['date'], 'yyyy-MM-dd', $null)
            $tasks += [pscustomobject]@{
                Completed = ($matches['state'].ToLower() -eq 'x')
                Date      = $dateValue
                Task      = $matches['task'].Trim()
                Section   = (Get-SectionTag -H2 $h2 -H3 $h3 -H4 $h4)
            }
        }
    }

    return $tasks
}

function Resolve-DdlPath {
    param(
        [string]$BaseDir,
        [string]$ConfiguredName
    )

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($ConfiguredName)) {
        $candidates += (Join-Path $BaseDir $ConfiguredName)
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    $fallback = Get-ChildItem -LiteralPath $BaseDir -File |
        Where-Object {
            $_.Extension -eq '.md' -and (
                $_.Name -like 'DDL*.md' -or
                $_.Name -like '*清单*.md' -or
                $_.Name -like '*ddl*.md'
            )
        } |
        Sort-Object Name |
        Select-Object -First 1

    if ($fallback) {
        return $fallback.FullName
    }

    throw "DDL file not found under $BaseDir"
}

function Get-DueLabel {
    param(
        [DateTime]$Today,
        [DateTime]$DueDate
    )

    $days = [int][Math]::Floor(($DueDate.Date - $Today.Date).TotalDays)
    if ($days -lt 0) {
        $late = [Math]::Abs($days)
        if ($late -eq 1) {
            return '逾期 1 天'
        }
        return "逾期 $late 天"
    }
    if ($days -eq 0) {
        return '今天'
    }
    if ($days -eq 1) {
        return '明天'
    }
    return ('{0} 天后' -f $days)
}

function Resolve-YouTubeChannelId {
    param([string]$Url)

    if ($Url -match '/channel/(UC[\w-]+)') {
        return $matches[1]
    }

    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -Headers @{ 'User-Agent' = 'Mozilla/5.0' }
    if ($response.Content -match '"externalId":"(UC[\w-]+)"') {
        return $matches[1]
    }

    throw "Unable to resolve YouTube channel id from $Url"
}

function Get-ArxivPapers {
    param(
        [hashtable]$Topic,
        [int]$MaxResults = 2
    )

    $encodedQuery = [System.Uri]::EscapeDataString($Topic.ArxivQuery)
    $uri = 'https://export.arxiv.org/api/query?search_query={0}&start=0&max_results={1}&sortBy=lastUpdatedDate&sortOrder=descending' -f $encodedQuery, $MaxResults
    $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -Headers @{ 'User-Agent' = 'LearningResearchDailyPush/1.0' }
    [xml]$xml = $response.Content

    $items = @()
    foreach ($entry in @($xml.feed.entry)) {
        if (-not $entry) {
            continue
        }

        $authors = @()
        foreach ($author in @($entry.author)) {
            if ($author.name) {
                $authors += $author.name
            }
        }

        $pdfLink = ''
        foreach ($link in @($entry.link)) {
            if ($link.title -eq 'pdf') {
                $pdfLink = $link.href
                break
            }
        }
        if (-not $pdfLink) {
            $pdfLink = ($entry.id -replace '^http://', 'https://')
        }

        $items += [pscustomobject]@{
            Topic     = $Topic.Name
            Title     = (Normalize-Text $entry.title)
            Summary   = (Normalize-Text $entry.summary)
            Authors   = ($authors -join ', ')
            Published = [DateTime]$entry.published
            Updated   = [DateTime]$entry.updated
            Link      = $pdfLink
            Source    = 'arXiv'
        }
    }

    return $items
}

function Get-GitHubProjects {
    param(
        [hashtable]$Topic,
        [int]$MaxResults = 2
    )

    $query = "$($Topic.GithubQuery) in:name,description,readme fork:false"
    $encodedQuery = [System.Uri]::EscapeDataString($query)
    $uri = 'https://api.github.com/search/repositories?q={0}&sort=updated&order=desc&per_page={1}' -f $encodedQuery, $MaxResults
    $headers = @{
        'Accept' = 'application/vnd.github+json'
        'User-Agent' = 'LearningResearchDailyPush/1.0'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    $response = Invoke-RestMethod -Uri $uri -Headers $headers

    $items = @()
    foreach ($repo in @($response.items)) {
        if (-not $repo) {
            continue
        }

        $language = 'Unknown'
        if ($repo.language) {
            $language = $repo.language
        }

        $items += [pscustomobject]@{
            Topic       = $Topic.Name
            Name        = $repo.full_name
            Description = (Normalize-Text $repo.description)
            Stars       = [int]$repo.stargazers_count
            Language    = $language
            Updated     = [DateTime]$repo.updated_at
            Link        = $repo.html_url
        }
    }

    return $items
}

function Get-LatestVideos {
    param(
        [array]$Feeds,
        [int]$MaxResults = 5
    )

    $videos = @()
    foreach ($feed in $Feeds) {
        try {
            $channelId = Resolve-YouTubeChannelId -Url $feed.Url
            $rssUrl = 'https://www.youtube.com/feeds/videos.xml?channel_id={0}' -f $channelId
            $response = Invoke-WebRequest -Uri $rssUrl -UseBasicParsing -Headers @{ 'User-Agent' = 'LearningResearchDailyPush/1.0' }
            [xml]$xml = $response.Content

            foreach ($entry in @($xml.feed.entry | Select-Object -First 2)) {
                if (-not $entry) {
                    continue
                }

                $link = ''
                foreach ($candidate in @($entry.link)) {
                    if ($candidate.href) {
                        $link = $candidate.href
                        break
                    }
                }

                if (-not $link -and $entry.videoId) {
                    $link = 'https://www.youtube.com/watch?v={0}' -f $entry.videoId
                }

                $videos += [pscustomobject]@{
                    Topic     = $feed.Topic
                    Channel   = $feed.Name
                    Title     = (Normalize-Text $entry.title)
                    Published = [DateTime]$entry.published
                    Link      = $link
                }
            }
        }
        catch {
            Write-Warning "Video feed failed for $($feed.Name): $($_.Exception.Message)"
        }
    }

    return $videos |
        Sort-Object Published -Descending |
        Select-Object -First $MaxResults
}

function Format-TaskTable {
    param([array]$Tasks)

    if (-not $Tasks -or $Tasks.Count -eq 0) {
        return @('_无_')
    }

    $lines = @(
        '| 日期 | 任务 | 所属模块 | 状态 |'
        '|:---:|:---|:---|:---:|'
    )
    foreach ($task in $Tasks) {
        $dateLabel = '{0:MM-dd} {1}' -f $task.Date, (Get-WeekdayCn $task.Date)
        $status = Get-DueLabel -Today $script:Today -DueDate $task.Date
        $lines += "| $dateLabel | $($task.Task) | $($task.Section) | $status |"
    }

    return $lines
}

function Format-PaperBlock {
    param([array]$Papers)

    if (-not $Papers -or $Papers.Count -eq 0) {
        return @('_今日未抓到 arXiv 结果_')
    }

    $lines = @()
    $grouped = $Papers | Group-Object Topic
    foreach ($group in $grouped) {
        $lines += "### $($group.Name)"
        $lines += ''
        foreach ($paper in $group.Group) {
            $summary = $paper.Summary
            if ($summary.Length -gt 180) {
                $summary = $summary.Substring(0, 180).TrimEnd() + '...'
            }

            $lines += "- [$($paper.Title)]($($paper.Link))"
            $lines += "  作者：$($paper.Authors)"
            $lines += "  更新时间：$('{0:yyyy-MM-dd}' -f $paper.Updated)"
            $lines += "  摘要：$summary"
            $lines += ''
        }
    }

    return $lines
}

function Format-VideoBlock {
    param([array]$Videos)

    if (-not $Videos -or $Videos.Count -eq 0) {
        return @('_今日未抓到视频更新_')
    }

    $lines = @()
    foreach ($video in $Videos) {
        $lines += "- [$($video.Title)]($($video.Link))"
        $lines += "  频道：$($video.Channel) | 方向：$($video.Topic) | 发布时间：$('{0:yyyy-MM-dd}' -f $video.Published)"
    }

    return $lines
}

function Format-ProjectBlock {
    param([array]$Projects)

    if (-not $Projects -or $Projects.Count -eq 0) {
        return @('_今日未抓到开源项目更新_')
    }

    $lines = @()
    $grouped = $Projects | Group-Object Topic
    foreach ($group in $grouped) {
        $lines += "### $($group.Name)"
        $lines += ''
        foreach ($project in $group.Group) {
            $lines += "- [$($project.Name)]($($project.Link))"
            $lines += "  Stars：$($project.Stars) | 语言：$($project.Language) | 最近更新：$('{0:yyyy-MM-dd}' -f $project.Updated)"
            if ($project.Description) {
                $lines += "  简介：$($project.Description)"
            }
            $lines += ''
        }
    }

    return $lines
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

$config = Import-PowerShellDataFile -LiteralPath $ConfigPath
$baseDir = Split-Path -Parent $ConfigPath
$outputDir = Resolve-Path -LiteralPath (Join-Path $baseDir $config.OutputDirectory)
$ddlPath = Resolve-DdlPath -BaseDir $baseDir -ConfiguredName $config.DdlFileName
$logDir = Join-Path $baseDir 'logs'

if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

$script:Today = Get-Date
$dateLabel = '{0:yyyy-MM-dd}' -f $script:Today
$fileDateLabel = '{0:yyyy.MM.dd}' -f $script:Today
$weekdayLabel = Get-WeekdayCn $script:Today
$outputFile = Join-Path $outputDir ('{0} 学习与科研日推.md' -f $fileDateLabel)
$logFile = Join-Path $logDir ('{0}-run.log' -f $dateLabel)

Start-Transcript -LiteralPath $logFile -Force | Out-Null

try {
    $allTasks = Parse-DdlTasks -Path $ddlPath
    $openTasks = $allTasks |
        Where-Object { -not $_.Completed } |
        Sort-Object Date, Task

    $overdueTasks = $openTasks | Where-Object { $_.Date.Date -lt $script:Today.Date }
    $todayTasks = $openTasks | Where-Object { $_.Date.Date -eq $script:Today.Date }
    $nextThreeDays = $openTasks | Where-Object {
        $_.Date.Date -gt $script:Today.Date -and
        $_.Date.Date -le $script:Today.Date.AddDays(3)
    }
    $nextSevenDays = $openTasks | Where-Object {
        $_.Date.Date -gt $script:Today.Date.AddDays(3) -and
        $_.Date.Date -le $script:Today.Date.AddDays(7)
    }

    $paperItems = @()
    $projectItems = @()
    foreach ($topic in $config.Topics) {
        try {
            $paperItems += Get-ArxivPapers -Topic $topic -MaxResults 2
        }
        catch {
            Write-Warning "arXiv fetch failed for $($topic.Name): $($_.Exception.Message)"
        }

        try {
            $projectItems += Get-GitHubProjects -Topic $topic -MaxResults 2
        }
        catch {
            Write-Warning "GitHub fetch failed for $($topic.Name): $($_.Exception.Message)"
        }
    }

    $paperItems = $paperItems |
        Sort-Object Updated -Descending |
        Group-Object Title |
        ForEach-Object { $_.Group | Select-Object -First 1 }

    $projectItems = $projectItems |
        Sort-Object Updated -Descending |
        Group-Object Name |
        ForEach-Object { $_.Group | Select-Object -First 1 }

    $videoItems = Get-LatestVideos -Feeds $config.VideoFeeds -MaxResults 6

    $content = @()
    $content += ('# 学习与科研日推 - {0} ({1})' -f $fileDateLabel, $weekdayLabel)
    $content += ''
    $content += '---'
    $content += ''
    $content += '## DDL 提醒'
    $content += ''
    $content += "### 逾期未完成（$($overdueTasks.Count)）"
    $content += Format-TaskTable -Tasks $overdueTasks
    $content += ''
    $content += "### 今日截止（$($todayTasks.Count)）"
    $content += Format-TaskTable -Tasks $todayTasks
    $content += ''
    $content += "### 未来 3 天（$($nextThreeDays.Count)）"
    $content += Format-TaskTable -Tasks $nextThreeDays
    $content += ''
    $content += "### 未来 7 天（$($nextSevenDays.Count)）"
    $content += Format-TaskTable -Tasks $nextSevenDays
    $content += ''
    $content += "### 未完成 DDL 全量清单（$($openTasks.Count)）"
    $content += ''
    foreach ($task in $openTasks) {
        $content += ('- [ ] {0:yyyy-MM-dd} {1}  [{2}]' -f $task.Date, $task.Task, $task.Section)
    }
    $content += ''
    $content += '## arXiv 论文'
    $content += ''
    $content += Format-PaperBlock -Papers $paperItems
    $content += ''
    $content += '## 视频更新'
    $content += ''
    $content += Format-VideoBlock -Videos $videoItems
    $content += ''
    $content += '## 开源项目'
    $content += ''
    $content += Format-ProjectBlock -Projects $projectItems
    $content += ''
    $content += '---'
    $content += ''
    $content += "*自动生成：PowerShell + arXiv + GitHub + YouTube RSS*"

    Set-Content -LiteralPath $outputFile -Value $content -Encoding UTF8
    & (Join-Path $PSScriptRoot 'build_dashboard_data.ps1') -DigestDir $outputDir -DdlPath $ddlPath -OutputDir (Join-Path $baseDir $config.DashboardDataDirectory)
}
finally {
    Stop-Transcript | Out-Null
}
