$configPath = Join-Path $PSScriptRoot 'research_digest_config.psd1'
$config = if (Test-Path -LiteralPath $configPath) {
    Import-PowerShellDataFile -LiteralPath $configPath
} else {
    $null
}

$scheduleText = if ($config.WeeklyReportTime) { $config.WeeklyReportTime } else { 'Sunday 20:00' }
if ($scheduleText -notmatch '^(?<day>[A-Za-z]+)\s+(?<time>\d{1,2}:\d{2})$') {
    throw "WeeklyReportTime must use the format 'Sunday 20:00'. Actual: $scheduleText"
}

$dayOfWeek = $matches['day']
$timeText = $matches['time']

if (-not [System.Enum]::IsDefined([System.DayOfWeek], $dayOfWeek)) {
    throw "WeeklyReportTime day must be a valid DayOfWeek. Actual: $dayOfWeek"
}

$parsedTime = $null
if (-not [datetime]::TryParseExact($timeText, 'H:mm', $null, [System.Globalization.DateTimeStyles]::None, [ref]$parsedTime) -and
    -not [datetime]::TryParseExact($timeText, 'HH:mm', $null, [System.Globalization.DateTimeStyles]::None, [ref]$parsedTime)) {
    throw "WeeklyReportTime time must be a valid 24-hour time. Actual: $timeText"
}

$scriptPath = Join-Path $PSScriptRoot 'generate_weekly_report.ps1'
$action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument "-File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $dayOfWeek -At $parsedTime

Register-ScheduledTask -TaskName 'LearningResearchWeeklyReport' -Action $action -Trigger $trigger -Force
