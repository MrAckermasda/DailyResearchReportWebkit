function Test-DocxReadable {
    param([Parameter(Mandatory)][string]$Path)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($zip) {
            $zip.Dispose()
        }
    }
}

function Get-WeeklyTemplatePath {
    param(
        [Parameter(Mandatory)][string]$WeeklyReportDir,
        [string]$TemplatePath,
        [string]$ExcludePath
    )

    if ($TemplatePath) {
        $resolved = (Resolve-Path -LiteralPath $TemplatePath).Path
        if (-not (Test-DocxReadable -Path $resolved)) {
            throw "Template .docx is not readable: $resolved"
        }
        return $resolved
    }

    $candidates = Get-ChildItem -LiteralPath $WeeklyReportDir -File -Filter '*.docx' |
        Sort-Object LastWriteTime -Descending

    foreach ($candidate in $candidates) {
        if ($ExcludePath -and ([System.IO.Path]::GetFullPath($candidate.FullName) -eq [System.IO.Path]::GetFullPath($ExcludePath))) {
            continue
        }

        if (Test-DocxReadable -Path $candidate.FullName) {
            return $candidate.FullName
        }
    }

    throw "No readable weekly report template .docx found under $WeeklyReportDir"
}

function Convert-ToWordXmlText {
    param([Parameter(Mandatory)][string]$Text)

    $escaped = [System.Security.SecurityElement]::Escape($Text)
    return $escaped -replace "`r?`n", '</w:t><w:br/><w:t xml:space="preserve">'
}

function New-WeeklyParagraphXml {
    param(
        [Parameter(Mandatory)][string]$Text
    )

    $wordText = Convert-ToWordXmlText -Text $Text
    return "<w:p><w:r><w:t xml:space=""preserve"">$wordText</w:t></w:r></w:p>"
}

function Write-DocxFromTemplate {
    param(
        [Parameter(Mandatory)][string]$TemplatePath,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string[]]$Paragraphs
    )

    Copy-Item -LiteralPath $TemplatePath -Destination $OutputPath -Force

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::Open($OutputPath, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq 'word/document.xml' } | Select-Object -First 1
        if (-not $entry) {
            throw 'word/document.xml not found in template'
        }

        $reader = New-Object System.IO.StreamReader($entry.Open())
        $xml = $reader.ReadToEnd()
        $reader.Dispose()

        $paragraphXml = ($Paragraphs | ForEach-Object { New-WeeklyParagraphXml -Text $_ }) -join ''
        $xml = [regex]::Replace($xml, '(?s)(<w:body>).*?(<w:sectPr\b.*?</w:sectPr>)', "`$1$paragraphXml`$2")

        $entry.Delete()
        $newEntry = $zip.CreateEntry('word/document.xml')
        $writer = New-Object System.IO.StreamWriter($newEntry.Open())
        $writer.Write($xml)
        $writer.Dispose()
    }
    finally {
        $zip.Dispose()
    }
}

Export-ModuleMember -Function Get-WeeklyTemplatePath, Write-DocxFromTemplate
