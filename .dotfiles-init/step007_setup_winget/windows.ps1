#!/usr/bin/env pwsh

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Update-SettingsJson {
    $source = "$(Join-Path (Split-Path ${PSCommandPath}) "settings.json")"
    $target = "${env:LOCALAPPDATA}\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json"

    Write-Log "Copy 'settings.json' ..."
    Write-Log "    from:   ${source}"
    Write-Log "    to:     ${target}"

    New-Item (Split-Path "${target}") -ItemType "Directory" -Force > $null
    Copy-Item -Path "${source}" -Destination "${target}"

    Write-Log " -> Copied."
}

function Step7 {
    Write-Step 7 "Setup WinGet"

    Update-WinGetPackage "Microsoft.AppInstaller"
    Write-CommandLog { winget --version }

    Update-SettingsJson
}

if ((-not ${MyInvocation}.ScriptName) -or (${MyInvocation}.ScriptName -ne "${PSCommandPath}")) {
    Import-Module -Name "$(Join-Path ("${PSCommandPath}" | Split-Path | Split-Path) "windows_utils.psm1")" -Force
    Step7 -Args $args
}
