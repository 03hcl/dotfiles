#!/usr/bin/env pwsh

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Step8 {
    Write-Step 8 "Install Visual Studio Code"

    Update-WinGetPackage "Microsoft.VisualStudioCode"
    Import-Path

    Write-CommandLog { code --version }

    Write-Step 8 "Install Extensions for Visual Studio Code"

    code --install-extension "mhutchie.git-graph" --force
    code --install-extension "ms-ceintl.vscode-language-pack-ja" --force
    code --install-extension "ms-vscode.powershell" --force
}

if ((-not ${MyInvocation}.ScriptName) -or (${MyInvocation}.ScriptName -ne "${PSCommandPath}")) {
    Import-Module -Name "$(Join-Path ("${PSCommandPath}" | Split-Path | Split-Path) "windows_utils.psm1")" -Force
    Step8 -Args $args
}
