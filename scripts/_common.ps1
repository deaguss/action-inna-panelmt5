# Shared helpers for link-mt5.ps1 and build.ps1 (dot-sourced, Windows PowerShell 5.1 or later).

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
