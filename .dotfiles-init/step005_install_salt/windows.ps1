#!/usr/bin/env pwsh

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Step5 {
    Write-Step 5 "Install Salt Minion"

    # TODO: Solve the following error:
    #   InternetOpenUrl() failed. 0x80072ee7 : unknown error
    Update-WinGetPackage "SaltStack.SaltMinion"
    Import-Path

    Write-Command-Log { salt-call grains.items }
}

if ((-not ${MyInvocation}.ScriptName) -or (${MyInvocation}.ScriptName -ne ${PSCommandPath})) {
    . (Join-Path (Split-Path (Split-Path ${PSCommandPath})) "windows.ps1")
    Step5 -Args $args
}
