$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = [IO.Directory]::GetParent($PSScriptRoot).FullName
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('everything-zh-cn-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox | Out-Null

try {
    New-Item -ItemType File -Path (Join-Path $sandbox 'Everything.exe') | Out-Null
    [IO.File]::WriteAllText((Join-Path $sandbox 'Everything.ini'), "[Everything]`r`nlanguage=0`r`nrun_as_admin=1`r`n", [Text.UTF8Encoding]::new($false))

    & (Join-Path $PSScriptRoot 'Install-EverythingZhCn.ps1') -EverythingDir $sandbox -NoRestart
    $installedIni = [IO.File]::ReadAllText((Join-Path $sandbox 'Everything.ini'))
    if ($installedIni -notmatch '(?m)^language=2052(?=\r?$)') { throw '安装后语言值不正确。' }
    if (-not (Test-Path -LiteralPath (Join-Path $sandbox 'Everything.lng'))) { throw '安装后缺少语言包。' }

    & (Join-Path $PSScriptRoot 'Uninstall-EverythingZhCn.ps1') -EverythingDir $sandbox -NoRestart
    $restoredIni = [IO.File]::ReadAllText((Join-Path $sandbox 'Everything.ini'))
    if ($restoredIni -notmatch '(?m)^language=0(?=\r?$)') { throw '卸载后没有恢复原语言值。' }
    if (Test-Path -LiteralPath (Join-Path $sandbox 'Everything.lng')) { throw '卸载后语言包仍然存在。' }

    Write-Host 'PASS：安装、简中切换与还原测试全部通过。'
} finally {
    if (Test-Path -LiteralPath $sandbox) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force
    }
}
