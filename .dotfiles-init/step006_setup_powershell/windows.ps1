#!/usr/bin/env pwsh

[CmdletBinding(SupportsShouldProcess = $true)]
param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Args)

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

function Update-PowerShellProfile {
    Write-CommandLog { ${PROFILE} | Format-List -Force }

    $target = (powershell -NoProfile -Command "`${PROFILE}.CurrentUserAllHosts")
    Copy-Resource -Source "profile.ps1" -Target "${target}" > $null
    $target = (pwsh -NoProfile -Command "`${PROFILE}.CurrentUserAllHosts")
    Copy-Resource -Source "profile.ps1" -Target "${target}" > $null
}

function Update-ExecutionPolicy {
    Set-ExecutionPolicy -ExecutionPolicy "RemoteSigned" -Scope "CurrentUser"
    Write-Log
    Write-CommandLog { Get-ExecutionPolicy -List }
}

function Enable-DeveloperMode {
    $key = "SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
    $value = "AllowDevelopmentWithoutDevLicense"
    $type = "DWord"
    $data = "1"

    $path = "HKLM:\${key}"

    if (Test-Path "${path}") {
        $prop = Get-ItemProperty "${path}"
        if (${prop} -and ${prop}."${value}" -eq "${data}") { return }
    }

    Start-Process pwsh -Verb "RunAs" -Wait -ArgumentList @(
        "-NoProfile",
        "-Command",
        "Set-ItemProperty -Path '${path}' -Name '${value}' -Value '${data}' -PropertyType '${type}' -Force"
    )
}

function Install-BusyBox {
    Update-WinGetPackage "frippery.busybox-w32"
    New-WinGetPackageLink -Id "frippery.busybox-w32" -Command "busybox"
    Import-Path

    Write-CommandLog { busybox | busybox head -n 2 }
}

function Install-Cygwin {
    Update-WinGetPackage "Cygwin.Cygwin"

    $root = "C:\cygwin64"
    $paths = (
        "${root}\bin",
        "${root}\sbin",
        "${root}\usr\bin",
        "${root}\usr\sbin",
        "${root}\usr\local\bin"
    )
    foreach ($p in ${paths}) { Update-Path "${p}" }
    $libs = (
        "${root}\lib",
        "${root}\lib\w32api",
        "${root}\usr\lib",
        "${root}\usr\local\lib"
    )
    Update-Path -ForceFirst -Key "LD_LIBRARY_PATH" @(${libs})

    Write-CommandLog { cygcheck -c cygwin }
}

function Install-CygwinPackages {
    $packages = @(
        # "automake",
        "bash-completion",
        "build-essential",
        "ca-certificates",
        "cmake",
        "curl",
        "dnsutils",
        "gawk",
        "gcc-core",
        # "gcc-fortran",
        "gcc-g++",
        "gdb",
        "htop",
        "iputils-ping",
        "less",
        # "libboost-devel",
        "make",
        "openssh",
        "openssl",
        # "patch",
        "perl",
        "rsync",
        "tar",
        "tree",
        "unzip",
        "vim",
        "wget",
        "xxd",
        "zip"
    )
    $src = "https://cygwin.com/setup-x86_64.exe"
    $script = Get-OnlineResource -Source "${src}" -TargetDir "$(Get-TempDir)\cygwin"

    Start-Process -FilePath "${script}" -Wait -ArgumentList @(
        "--quiet-mode",
        "--upgrade-also",
        "--packages",
        "$(${packages} -join ',')"
    )

    Write-CommandLog { cygcheck -c }
}

function Install-Jq {
    Update-WinGetPackage "jqlang.jq"
    # New-SymLink -Source "${env:LOCALAPPDATA}\Microsoft\WinGet\Links\jq.exe"
    New-WinGetPackageLink -Id "jqlang.jq" -Command "jq"
    Import-Path

    Write-CommandLog { jq --version }
}

function Step6 {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Args)

    Write-Step 6 "Setup PowerShell"

    Update-PowerShell
    Update-PowerShellProfile
    Update-ExecutionPolicy

    . ${PROFILE}.CurrentUserAllHosts

    # Enable-DeveloperMode

    $commonParams = Get-CommonParameters $PSBoundParameters
    Update-Path @commonParams -ForceFirst `
        "%USERPROFILE%\.local\bin" `
        "%LOCALAPPDATA%\Microsoft\WinGet\Links"

    Write-CommandLog { Get-ChildItem "${env:APPDATA}\Microsoft\Windows\PowerShell\PSReadLine" }
    Write-CommandLog { Get-PSReadLineOption }
    Write-CommandLog { Get-PSReadLineKeyHandler }

    Install-BusyBox
    # Install-Cygwin
    # Install-CygwinPackages
    Install-Jq
}

if ((-not ${MyInvocation}.ScriptName) -or (${MyInvocation}.ScriptName -ne "${PSCommandPath}")) {
    Import-Module -Name "$(Join-Path ("${PSCommandPath}" | Split-Path | Split-Path) "windows_utils.psm1")" -Force
    Step6 @PSBoundParameters -Args ${Args}
}
