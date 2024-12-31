#!/usr/bin/env pwsh

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Update-PowerShell {
    Update-WinGetPackage "Microsoft.PowerShell"

    # Reference:
    #   https://learn.microsoft.com/ja-jp/powershell/scripting/install/installing-powershell-on-windows
    $pwshPath = "${env:ProgramFiles}\PowerShell\7"
    if (-not (${env:Path}.Split(';') -contains "${pwshPath}")) {
        [Environment]::SetEnvironmentVariable("Path", "${pwshPath};${env:Path}", "User")
    }
    Import-Path

    Write-CommandLog { pwsh --version }
    Write-CommandLog { ${Host} }
}

function Update-Profile {
    Write-CommandLog { ${PROFILE} | Format-List -Force }
    Copy-Resource -Source "profile.ps1" -Target ${PROFILE}.CurrentUserAllHosts
}

function Update-ExecutionPolicy {
    Set-ExecutionPolicy -ExecutionPolicy "RemoteSigned" -Scope "CurrentUser"
    Write-Log
    Write-CommandLog { Get-ExecutionPolicy -List }
}

function Install-BusyBox {
    Update-WinGetPackage "frippery.busybox-w32"
    Import-Path
    Write-CommandLog { busybox | busybox head -n 2 }
}

function Step9 {
    Write-Step 9 "Setup PowerShell"

    Update-PowerShell
    Update-Profile
    Update-ExecutionPolicy

    . ${PROFILE}.CurrentUserAllHosts

    # Write-CommandLog { Get-ChildItem "${env:APPDATA}\Microsoft\Windows\PowerShell\PSReadLine" }
    # Write-CommandLog { Get-PSReadLineOption }
    # Write-CommandLog { Get-PSReadLineKeyHandler }

    Install-BusyBox
}

if ((-not ${MyInvocation}.ScriptName) -or (${MyInvocation}.ScriptName -ne "${PSCommandPath}")) {
    Import-Module -Name "$(Join-Path ("${PSCommandPath}" | Split-Path | Split-Path) "windows_utils.psm1")" -Force
    Step9 -Args $args
}
