# Shared helpers for link-mt5.ps1, build.ps1 and install.ps1 (dot-sourced, Windows PowerShell 5.1 or later).

# Reads a text file whatever MetaQuotes wrote it in: MT5 writes origin.txt and MetaEditor writes
# its compile logs as UTF-16LE.
function Read-TextAuto([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    # UTF-16LE without a byte order mark has a zero in every second byte of ASCII text.
    if ($bytes.Length -ge 2 -and $bytes[1] -eq 0) {
        return [Text.Encoding]::Unicode.GetString($bytes)
    }
    return [Text.Encoding]::Default.GetString($bytes)
}

# The MT5 data folders of this Windows user, with the install folder each came from (origin.txt).
function Get-Terminals {
    $root = Join-Path $env:APPDATA 'MetaQuotes\Terminal'
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    Get-ChildItem -LiteralPath $root -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'MQL5') } |
        ForEach-Object {
            $origin = Join-Path $_.FullName 'origin.txt'
            $install = ''
            if (Test-Path -LiteralPath $origin) { $install = (Read-TextAuto $origin).Trim() }
            [pscustomobject]@{ DataFolder = $_.FullName; Install = $install }
        }
}

# metaeditor64.exe of the first terminal, of those the data folders belong to, that has one;
# '' when none has.
function Find-MetaEditor([string[]]$DataFolders) {
    foreach ($folder in $DataFolders) {
        $origin = Join-Path $folder 'origin.txt'
        if (Test-Path -LiteralPath $origin) {
            $candidate = Join-Path (Read-TextAuto $origin).Trim() 'metaeditor64.exe'
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
        # A portable terminal keeps its data next to the exe.
        $candidate = Join-Path $folder 'metaeditor64.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return ''
}

function Test-Junction([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

# cmd's rmdir removes only the link. In Windows PowerShell 5.1, Remove-Item -Recurse follows a
# junction and deletes the files it points to (here: the repository), so it is never used on one.
function Remove-Junction([string]$Path) {
    cmd /c rmdir "$Path" | Out-Null
}
