#!/usr/bin/env pwsh

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Update-PowerShell {
    Update-WinGetPackage "Microsoft.PowerShell"

    # Reference:
    #   https://learn.microsoft.com/ja-jp/powershell/scripting/install/installing-powershell-on-windows
    Update-Path "${env:ProgramFiles}\PowerShell\7\"

    Write-CommandLog { pwsh --version }
    Write-CommandLog { ${Host} }
}

function Update-Profile {
    Write-CommandLog { ${PROFILE} | Format-List -Force }

    $target = (powershell -NoProfile -Command "`${PROFILE}.CurrentUserAllHosts")
    Copy-Resource -Source "profile.ps1" -Target "${target}"
    $target = (pwsh -NoProfile -Command "`${PROFILE}.CurrentUserAllHosts")
    Copy-Resource -Source "profile.ps1" -Target "${target}"
}

function Update-ExecutionPolicy {
    Set-ExecutionPolicy -ExecutionPolicy "RemoteSigned" -Scope "CurrentUser"
    Write-Log
    Write-CommandLog { Get-ExecutionPolicy -List }
}

# function Enable-DeveloperMode {
#     $keyName = "SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
#     $valueName = "AllowDevelopmentWithoutDevLicense"
#     $type = "DWord"
#     $data = "1"

#     $path = "HKLM:\${keyName}"

#     if (Test-Path "${path}") {
#         $prop = Get-ItemProperty "${path}"
#         if (${prop} -and ${prop}."${valueName}" -eq "${data}") { return }
#     }

#     Start-Process pwsh -Verb "RunAs" -Wait -ArgumentList @(
#         "-NoProfile",
#         "-Command",
#         "Set-ItemProperty -Path '${path}' -Name '${valueName}' -Value '${data}' -Type '${type}'"
#     )
# }

function Install-BusyBox {
    Update-WinGetPackage "frippery.busybox-w32"
    New-SymLink -Source `
        "${env:LOCALAPPDATA}\Microsoft\WinGet\Packages\frippery.busybox-w32_Microsoft.Winget.Source_8wekyb3d8bbwe\busybox.exe"

    Write-CommandLog { busybox | busybox head -n 2 }
}

function Install-Jq {
    Update-WinGetPackage "jqlang.jq"
    Import-Path
    New-SymLink -Source "${env:LOCALAPPDATA}\Microsoft\WinGet\Links\jq.exe"

    Write-CommandLog { jq --version }
}

function Step9 {
    Write-Step 9 "Setup PowerShell"

    Update-PowerShell
    Update-Profile
    Update-ExecutionPolicy

    . ${PROFILE}.CurrentUserAllHosts

    # Enable-DeveloperMode
    Update-Path "%USERPROFILE%\.local\bin"
    Update-Path "%LOCALAPPDATA%\Microsoft\WinGet\Links"

    # Write-CommandLog { Get-ChildItem "${env:APPDATA}\Microsoft\Windows\PowerShell\PSReadLine" }
    # Write-CommandLog { Get-PSReadLineOption }
    # Write-CommandLog { Get-PSReadLineKeyHandler }

    Install-BusyBox
    Install-Jq
}

if ((-not ${MyInvocation}.ScriptName) -or (${MyInvocation}.ScriptName -ne "${PSCommandPath}")) {
    Import-Module -Name "$(Join-Path ("${PSCommandPath}" | Split-Path | Split-Path) "windows_utils.psm1")" -Force
    Step9 -Args $args
}
