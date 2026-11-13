#!/usr/bin/env pwsh

[CmdletBinding(SupportsShouldProcess = $true)]
param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Args)

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Update-VSCodeConfig {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$Name)

    if ($Name -eq "argv.json") { $targetDir = "${env:USERPROFILE}\.vscode" }
    else { $targetDir = "${env:APPDATA}\Code\User" }

    $target = Join-Path "${targetDir}" "${Name}"

    if (${PSCmdlet}.ShouldProcess("${target}", "Apply VS Code user configuration")) {
        Copy-Resource -Source "${Name}" -Target "${target}" > $null
    }
}

function Update-VSCodeConfigDirectory {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$Name)

    $sourceDir = Join-Path "${PSScriptRoot}" "${Name}"
    $targetDir = Join-Path "${env:APPDATA}\Code\User" "${Name}"

    if (${PSCmdlet}.ShouldProcess("${targetDir}", "Apply VS Code user configuration directory")) {
        New-Item -Path "${targetDir}" -ItemType "Directory" -Force > $null
        Get-ChildItem -LiteralPath "${sourceDir}" -File -Recurse `
        | Where-Object { $_.Name -ne ".gitignore" } `
        | ForEach-Object {
            $relativePath = $_.FullName.Substring("${sourceDir}".Length).TrimStart([char[]]@("\", "/"))
            $target = Join-Path "${targetDir}" "${relativePath}"
            $source = Join-Path "${Name}" "${relativePath}"
            Copy-Resource -Source "${source}" -Target "${target}" > $null
        }
    }
}

function Install-VSCodeExtensions {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$Path = (Join-Path "${PSScriptRoot}" "extensions.json"))

    $json = Get-Content -LiteralPath "${Path}" -Raw
    $json = [regex]::Replace($json, '(?s)/\*.*?\*/|//[^\r\n]*', '')
    $json = $json -replace ',\s*\]', ']' -replace ',\s*\}', '}'

    $extensions = (ConvertFrom-Json -InputObject "${json}").recommendations

    $installArgs = @()
    foreach ($extension in ${extensions}) {
        if (${PSCmdlet}.ShouldProcess("${extension}", "Install VS Code extension")) {
            $installArgs += "--install-extension", $extension
        }
    }
    if ($installArgs.Count -eq 0) { return }

    $optBackUp = $env:NODE_OPTIONS
    try {
        # NOTE: Suppress only the VS Code CLI's legacy URL warning.
        $env:NODE_OPTIONS = "${optBackUp} --disable-warning=DEP0169".Trim()
        Write-CommandLog { code @installArgs --force } -IsDirectOutput $true
    }
    finally { $env:NODE_OPTIONS = $optBackUp }
}

function Step8 {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Args)

    Write-Step 8 "Install Visual Studio Code"

    Update-WinGetPackage "Microsoft.VisualStudioCode"
    Import-Path

    if (-not ${WhatIfPreference}) { Write-CommandLog { code --version } }

    Update-VSCodeConfig -Name "argv.json"
    Update-VSCodeConfig -Name "chatLanguageModels.json"
    Update-VSCodeConfig -Name "keybindings.json"
    Update-VSCodeConfig -Name "mcp.json"
    Update-VSCodeConfig -Name "settings.json"
    Update-VSCodeConfig -Name "tasks.json"

    Update-VSCodeConfigDirectory -Name "snippets"
    Update-VSCodeConfigDirectory -Name "prompts"

    Write-Step 8 "Install Extensions for Visual Studio Code"

    Install-VSCodeExtensions
}

if ((-not ${MyInvocation}.ScriptName) -or (${MyInvocation}.ScriptName -ne "${PSCommandPath}")) {
    Import-Module -Name "$(Join-Path ("${PSCommandPath}" | Split-Path | Split-Path) "windows_utils.psm1")" -Force
    Step8 @PSBoundParameters
}
