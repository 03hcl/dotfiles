#!/usr/bin/env pwsh

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Remove-AppAlias ([string]$FileName) {
    # NOTE: `Join-Path a b c` syntax is not supported in PowerShell < 7.0
    $filePath = Join-Path "${env:LOCALAPPDATA}" "Microsoft"
    $filePath = Join-Path "${filePath}" "WindowsApps"
    $filePath = Join-Path "${filePath}" "${FileName}"
    if (Test-Path "${filePath}") { Remove-Item "${filePath}" }
}

function Step9 {
    Write-Step 9 "Install Python 3.12"

    Update-WinGetPackage "Python.Python.3.12"
    Remove-AppAlias "python.exe"
    Remove-AppAlias "python3.exe"
    Import-Path

    Write-CommandLog { python --version }
    Write-CommandLog { py -3.12 --version }

    Write-CommandLog { pip --version }
    Write-CommandLog { pip3 --version }
    Write-CommandLog { pip3.12 --version }

    Write-CommandLog { pip install --upgrade uv }

    Write-CommandLog { uv pip install --system --upgrade markitdown }

    Write-CommandLog { uv pip list --system }
    # Write-CommandLog { markitdown --version }
}

if ((-not ${MyInvocation}.ScriptName) -or (${MyInvocation}.ScriptName -ne "${PSCommandPath}")) {
    Import-Module -Name "$(Join-Path ("${PSCommandPath}" | Split-Path | Split-Path) "windows_utils.psm1")" -Force
    Step9 -Args $args
}
