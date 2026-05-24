function Get-DigestFiles {
    param([Parameter(Mandatory)][string]$BaseDir)

    $files = Get-ChildItem -LiteralPath $BaseDir -File -Filter '*.md' -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '^\d{4}\.\d{2}\.\d{2} 学习与科研日推\.md$' -or
            $_.Name -match '^\d{4}-\d{2}-\d{2}-科研日推\.md$'
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
