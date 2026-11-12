#!/usr/bin/env pwsh

[CmdletBinding(SupportsShouldProcess = $true)]
param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Args)

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Step8 {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Args)

    Write-Step 8 "Install Visual Studio Code"

    Update-WinGetPackage "Microsoft.VisualStudioCode"
    Import-Path

    if (-not ${WhatIfPreference}) { Write-CommandLog { code --version } }

    Write-Step 8 "Install Extensions for Visual Studio Code"

    foreach ($extension in @("mhutchie.git-graph", "ms-ceintl.vscode-language-pack-ja", "ms-vscode.powershell")) {
        if (${PSCmdlet}.ShouldProcess("${extension}", "Install VS Code extension")) {
            code --install-extension "${extension}" --force
        }
    }
}

if ((-not ${MyInvocation}.ScriptName) -or (${MyInvocation}.ScriptName -ne "${PSCommandPath}")) {
    Import-Module -Name "$(Join-Path ("${PSCommandPath}" | Split-Path | Split-Path) "windows_utils.psm1")" -Force
    Step8 @PSBoundParameters
}
