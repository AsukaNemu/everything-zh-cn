[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$EverythingDir,
    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$targetDirectory = [IO.Path]::GetFullPath($EverythingDir)
$everythingExe = Join-Path $targetDirectory 'Everything.exe'
$everythingIni = Join-Path $targetDirectory 'Everything.ini'
$targetLanguagePack = Join-Path $targetDirectory 'Everything.lng'
$stateDirectory = Join-Path $targetDirectory '.everything-zh-cn'
$statePath = Join-Path $stateDirectory 'state.json'
$backupLanguagePack = Join-Path $stateDirectory 'Everything.lng.original'
$projectRoot = [IO.Directory]::GetParent($PSScriptRoot).FullName
$sdkDirectory = Join-Path $projectRoot 'assets\sdk'

if (-not (Test-Path -LiteralPath $everythingExe -PathType Leaf)) {
    throw "指定目录中找不到 Everything.exe：$targetDirectory"
}
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw "找不到安装状态，无法安全还原：$statePath"
}

$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$isRunning = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq 'Everything.exe' }).Count -gt 0
if ($isRunning) {
    if (-not ('EverythingZhCnSdk.Native' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace EverythingZhCnSdk {
    public static class Native {
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern bool SetDllDirectory(string path);
        [DllImport("Everything32.dll", EntryPoint="Everything_Exit")] public static extern int Exit32();
        [DllImport("Everything64.dll", EntryPoint="Everything_Exit")] public static extern int Exit64();
    }
}
'@
    }
    [void][EverythingZhCnSdk.Native]::SetDllDirectory($sdkDirectory)
    try {
        $exitResult = if ([Environment]::Is64BitProcess) { [EverythingZhCnSdk.Native]::Exit64() } else { [EverythingZhCnSdk.Native]::Exit32() }
    } finally {
        [void][EverythingZhCnSdk.Native]::SetDllDirectory($null)
    }
    if (-not $exitResult) {
        Get-Process Everything -ErrorAction SilentlyContinue | ForEach-Object { [void]$_.CloseMainWindow() }
    }
    Start-Sleep -Seconds 1
}

$utf8 = [Text.UTF8Encoding]::new($false)
if (Test-Path -LiteralPath $everythingIni) {
    $text = [IO.File]::ReadAllText($everythingIni)
    if ($null -eq $state.originalLanguage) {
        $languageLinePattern = [regex]::new('(?m)^language=[^\r\n]*(?:\r?\n)?')
        $text = $languageLinePattern.Replace($text, '', 1)
    } elseif ([regex]::IsMatch($text, '(?m)^language=[^\r\n]*(?=\r?$)')) {
        $languagePattern = [regex]::new('(?m)^language=[^\r\n]*(?=\r?$)')
        $text = $languagePattern.Replace($text, "language=$($state.originalLanguage)", 1)
    } else {
        $sectionPattern = [regex]::new('(?m)^\[Everything\][ \t]*(?=\r?$)')
        $text = $sectionPattern.Replace($text, "[Everything]`r`nlanguage=$($state.originalLanguage)", 1)
    }
    [IO.File]::WriteAllText($everythingIni, $text, $utf8)
}

if ($state.hadLanguagePack) {
    if (-not (Test-Path -LiteralPath $backupLanguagePack -PathType Leaf)) {
        throw "原语言包备份丢失：$backupLanguagePack"
    }
    Copy-Item -LiteralPath $backupLanguagePack -Destination $targetLanguagePack -Force
} elseif (Test-Path -LiteralPath $targetLanguagePack) {
    Remove-Item -LiteralPath $targetLanguagePack -Force
}

if (-not $NoRestart) {
    Start-Process -FilePath $everythingExe
}

Write-Host "Everything 已恢复到汉化前状态：$targetDirectory"
Write-Host "备份记录仍保留在：$stateDirectory"
