#!/usr/bin/env pwsh

[CmdletBinding(SupportsShouldProcess = $true)]
param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Args)

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Update-SettingsJson {
    $target = "${env:LOCALAPPDATA}\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json"
    Copy-Resource -Source "settings.json" -Target "${target}" > $null
    # New-SymLink -Source "settings.json" -Target "${target}" > $null
}

function Step7 {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Args)

    Write-Step 7 "Setup WinGet"

    Update-WinGetPackage "Microsoft.AppInstaller"
    if (-not ${WhatIfPreference}) { Write-CommandLog { winget --version } }

    Update-SettingsJson
}

if ((-not ${MyInvocation}.ScriptName) -or (${MyInvocation}.ScriptName -ne "${PSCommandPath}")) {
    Import-Module -Name "$(Join-Path ("${PSCommandPath}" | Split-Path | Split-Path) "windows_utils.psm1")" -Force
    Step7 @PSBoundParameters
}
