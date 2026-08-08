[CmdletBinding()]
param(
    [string]$EverythingDir,
    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Find-EverythingDirectory {
    param([string]$ExplicitDirectory)

    if ($ExplicitDirectory) {
        $resolved = [IO.Path]::GetFullPath($ExplicitDirectory)
        if (-not (Test-Path -LiteralPath (Join-Path $resolved 'Everything.exe') -PathType Leaf)) {
            throw "指定目录中找不到 Everything.exe：$resolved"
        }
        return $resolved
    }

    $candidates = [Collections.Generic.List[string]]::new()
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq 'Everything.exe' -and $_.ExecutablePath } |
        ForEach-Object { $candidates.Add((Split-Path -LiteralPath $_.ExecutablePath -Parent)) }

    $uninstallRoots = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty $uninstallRoots -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'Everything*' -and $_.InstallLocation } |
        ForEach-Object { $candidates.Add($_.InstallLocation) }

    @(
        (Join-Path $env:ProgramFiles 'Everything'),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Everything' }),
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Everything')
    ) | Where-Object { $_ } | ForEach-Object { $candidates.Add($_) }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'Everything.exe') -PathType Leaf)) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }

    throw '未找到 Everything。请使用 -EverythingDir 指定包含 Everything.exe 的目录。'
}

function Stop-EverythingClient {
    param([string]$SdkDirectory)

    $running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq 'Everything.exe' })
    if ($running.Count -eq 0) { return }

    $sdk32 = Join-Path $SdkDirectory 'Everything32.dll'
    $sdk64 = Join-Path $SdkDirectory 'Everything64.dll'
    if (-not (Test-Path -LiteralPath $sdk32) -or -not (Test-Path -LiteralPath $sdk64)) {
        throw 'Everything 正在运行且 SDK 组件缺失。请手动退出 Everything 后重试。'
    }

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

    [void][EverythingZhCnSdk.Native]::SetDllDirectory($SdkDirectory)
    try {
        $exitResult = if ([Environment]::Is64BitProcess) {
            [EverythingZhCnSdk.Native]::Exit64()
        } else {
            [EverythingZhCnSdk.Native]::Exit32()
        }
    } finally {
        [void][EverythingZhCnSdk.Native]::SetDllDirectory($null)
    }
    if (-not $exitResult) {
        Get-Process Everything -ErrorAction SilentlyContinue | ForEach-Object { [void]$_.CloseMainWindow() }
    }

    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 200
        $stillRunning = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq 'Everything.exe' })
    } while ($stillRunning.Count -gt 0 -and [DateTime]::UtcNow -lt $deadline)

    if ($stillRunning.Count -gt 0) {
        throw 'Everything 未能正常退出。请手动退出后重新运行脚本。'
    }
}

function Get-LanguageValue {
    param([string]$IniPath)
    if (-not (Test-Path -LiteralPath $IniPath)) { return $null }
    $text = [IO.File]::ReadAllText($IniPath)
    $match = [regex]::Match($text, '(?m)^language=([^\r\n]*)(?=\r?$)')
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

function Set-LanguageValue {
    param([string]$IniPath, [string]$Value)
    $utf8 = [Text.UTF8Encoding]::new($false)
    $text = if (Test-Path -LiteralPath $IniPath) { [IO.File]::ReadAllText($IniPath) } else { "[Everything]`r`n" }
    if ([regex]::IsMatch($text, '(?m)^language=[^\r\n]*(?=\r?$)')) {
        $languagePattern = [regex]::new('(?m)^language=[^\r\n]*(?=\r?$)')
        $text = $languagePattern.Replace($text, "language=$Value", 1)
    } else {
        $sectionPattern = [regex]::new('(?m)^\[Everything\][ \t]*(?=\r?$)')
        $text = $sectionPattern.Replace($text, "[Everything]`r`nlanguage=$Value", 1)
    }
    [IO.File]::WriteAllText($IniPath, $text, $utf8)
}

$projectRoot = [IO.Directory]::GetParent($PSScriptRoot).FullName
$sourceLanguagePack = Join-Path $projectRoot 'assets\Everything.lng'
$sdkDirectory = Join-Path $projectRoot 'assets\sdk'
if (-not (Test-Path -LiteralPath $sourceLanguagePack -PathType Leaf)) {
    throw "项目语言包缺失：$sourceLanguagePack"
}

$targetDirectory = Find-EverythingDirectory -ExplicitDirectory $EverythingDir
$everythingExe = Join-Path $targetDirectory 'Everything.exe'
$everythingIni = Join-Path $targetDirectory 'Everything.ini'
$targetLanguagePack = Join-Path $targetDirectory 'Everything.lng'
$stateDirectory = Join-Path $targetDirectory '.everything-zh-cn'
$statePath = Join-Path $stateDirectory 'state.json'
$backupLanguagePack = Join-Path $stateDirectory 'Everything.lng.original'

Stop-EverythingClient -SdkDirectory $sdkDirectory

if (-not (Test-Path -LiteralPath $statePath)) {
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    $hadLanguagePack = Test-Path -LiteralPath $targetLanguagePack -PathType Leaf
    if ($hadLanguagePack) {
        Copy-Item -LiteralPath $targetLanguagePack -Destination $backupLanguagePack
    }
    $state = [ordered]@{
        schemaVersion = 1
        installedAt = [DateTime]::UtcNow.ToString('o')
        everythingDirectory = $targetDirectory
        iniExisted = (Test-Path -LiteralPath $everythingIni -PathType Leaf)
        originalLanguage = Get-LanguageValue -IniPath $everythingIni
        hadLanguagePack = $hadLanguagePack
    }
    $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
}

Copy-Item -LiteralPath $sourceLanguagePack -Destination $targetLanguagePack -Force
Set-LanguageValue -IniPath $everythingIni -Value '2052'

if (-not $NoRestart) {
    Start-Process -FilePath $everythingExe
}

Write-Host "Everything 简体中文已安装：$targetDirectory"
Write-Host '原始状态已保存，可使用 Uninstall-EverythingZhCn.ps1 恢复。'
