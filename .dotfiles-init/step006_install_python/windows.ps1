#!/usr/bin/env pwsh

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Remove-AppAlias ([string]$FileName) {
    # NOTE: `Join-Path a b c` syntax is not supported in PowerShell < 7.0
    $filePath = Join-Path "${env:LocalAppData}" "Microsoft"
    $filePath = Join-Path "${filePath}" "WindowsApps"
    $filePath = Join-Path "${filePath}" "${FileName}"
    if (Test-Path "${filePath}") { Remove-Item "${filePath}" }
}

function Step6 {
    Write-Step 6 "Install Python 3.12"

    Update-WinGetPackage "Python.Python.3.12"
    Remove-AppAlias "python.exe"
    Remove-AppAlias "python3.exe"
    Import-Path

    Write-Command-Log { python --version }
    Write-Command-Log { py -3.12 --version }

    Write-Command-Log { pip --version }
    Write-Command-Log { pip3 --version }
    Write-Command-Log { pip3.12 --version }

    Write-Command-Log { pip list }
    Write-Command-Log { pip install --upgrade uv }
}

if ((-not ${MyInvocation}.ScriptName) -or (${MyInvocation}.ScriptName -ne ${PSCommandPath})) {
    . (Join-Path (Split-Path (Split-Path ${PSCommandPath})) "windows.ps1")
    Step6 -Args $args
}
