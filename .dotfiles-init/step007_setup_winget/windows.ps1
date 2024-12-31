#!/usr/bin/env pwsh

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Update-SettingsJson {
    $target = "${env:LOCALAPPDATA}\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json"
    Copy-Resource -Source "settings.json" -Target "${target}"
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
