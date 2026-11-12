#!/usr/bin/env pwsh

[CmdletBinding(SupportsShouldProcess = $true)]
param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Args)

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Remove-AppAlias ([string]$FileName) {
    # NOTE: `Join-Path a b c` syntax is not supported in PowerShell < 7.0
    $filePath = Join-Path "${env:LOCALAPPDATA}" "Microsoft"
    $filePath = Join-Path "${filePath}" "WindowsApps"
    $filePath = Join-Path "${filePath}" "${FileName}"
    if (Test-Path -LiteralPath "${filePath}") { Remove-Item -LiteralPath "${filePath}" }
}

function Step9 {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Args)

    $minor = "14"

    Write-Step 9 "Install Python 3.${minor}"

    Update-WinGetPackage "Python.Python.3.${minor}"
    Remove-AppAlias "python.exe"
    Remove-AppAlias "python3.exe"
    Import-Path

    # NOTE: Link in the directory of python.exe. A venv made from a link in another directory (e.g. ~\.local\bin)
    #       looks for python.exe next to the link and fails ("did not find executable at ...")
    if (${WhatIfPreference}) {
        ${PSCmdlet}.ShouldProcess("Python 3.${minor} interpreter links", "Resolve interpreter and create python3.exe links") > $null
        ${PSCmdlet}.ShouldProcess("Python packages", "Upgrade uv and install markitdown") > $null
        return
    }

    $python = py -3.${minor} -c "import sys; print(sys.executable)"
    New-SymLink -Source "${python}" -TargetDir "$(Split-Path "${python}")" -TargetName "python3.exe"
    New-SymLink -Source "${python}" -TargetDir "$(Split-Path "${python}")" -TargetName "python3.${minor}.exe"

    Write-CommandLog { python --version }
    Write-CommandLog { python3 --version }
    Write-CommandLog { python3.${minor} --version }

    # Write-CommandLog { py --version }
    Write-CommandLog { py -3.${minor} --version }

    Write-CommandLog { pip --version }
    Write-CommandLog { pip3 --version }
    Write-CommandLog { pip3.${minor} --version }

    if (${PSCmdlet}.ShouldProcess("Python packages", "Run pip install --upgrade uv")) {
        Write-CommandLog { pip install --upgrade uv }
    }

    if (${PSCmdlet}.ShouldProcess("Python packages", "Run uv pip install --system --upgrade markitdown")) {
        Write-CommandLog { uv pip install --system --upgrade markitdown }
    }

    Write-CommandLog { uv pip list --system }
    # Write-CommandLog { markitdown --version }
}

if ((-not ${MyInvocation}.ScriptName) -or (${MyInvocation}.ScriptName -ne "${PSCommandPath}")) {
    Import-Module -Name "$(Join-Path ("${PSCommandPath}" | Split-Path | Split-Path) "windows_utils.psm1")" -Force
    Step9 @PSBoundParameters
}
