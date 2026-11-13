#!/usr/bin/env pwsh

[CmdletBinding(SupportsShouldProcess = $true)]
param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Args)

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Update-PowerShell {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSShouldProcess", "")]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    Update-WinGetPackage "Microsoft.PowerShell"

    # Reference:
    #   https://learn.microsoft.com/ja-jp/powershell/scripting/install/installing-powershell-on-windows
    Update-Path "${env:ProgramFiles}\PowerShell\7\"

    if (-not ${WhatIfPreference}) {
        Write-CommandLog { pwsh --version }
        Write-CommandLog { ${Host} }
    }
}

function Update-PowerShellProfile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if (-not ${PSCmdlet}.ShouldProcess("${env:USERPROFILE}", "Update Windows PowerShell and PowerShell profiles")) { return }

    Write-CommandLog { ${PROFILE} | Format-List -Force }

    $target = (powershell -NoProfile -Command "`${PROFILE}.CurrentUserAllHosts")
    Copy-Resource -Source "profile.ps1" -Target "${target}" > $null
    $target = (pwsh -NoProfile -Command "`${PROFILE}.CurrentUserAllHosts")
    Copy-Resource -Source "profile.ps1" -Target "${target}" > $null
}

function Update-ExecutionPolicy {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSShouldProcess", "")]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    Set-ExecutionPolicy -ExecutionPolicy "RemoteSigned" -Scope "CurrentUser"
    Write-Log
    if (-not ${WhatIfPreference}) { Write-CommandLog { Get-ExecutionPolicy -List } }
}

function Enable-DeveloperMode {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $key = "SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
    $value = "AllowDevelopmentWithoutDevLicense"
    $type = "DWord"
    $data = "1"

    $path = "HKLM:\${key}"

    if (Test-Path -LiteralPath "${path}") {
        $prop = Get-ItemProperty -LiteralPath "${path}"
        if (${prop} -and ${prop}."${value}" -eq "${data}") { return }
    }

    if (-not ${PSCmdlet}.ShouldProcess("${path}", "Enable Developer Mode")) { return }

    Start-Process pwsh -Verb "RunAs" -Wait -ArgumentList @(
        "-NoProfile",
        "-Command",
        "Set-ItemProperty -LiteralPath '${path}' -Name '${value}' -Value '${data}' -PropertyType '${type}' -Force"
    )
}

function Install-BusyBox {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    Update-WinGetPackage "frippery.busybox-w32"
    if (${PSCmdlet}.ShouldProcess("busybox", "Create WinGet package command link")) {
        New-WinGetPackageLink -Id "frippery.busybox-w32" -Command "busybox"
    }
    if (-not ${WhatIfPreference}) { Import-Path }

    if (-not ${WhatIfPreference}) { Write-CommandLog { busybox | busybox head -n 2 } }
}

function Install-Cygwin {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSShouldProcess", "")]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

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

    if (-not ${WhatIfPreference}) { Write-CommandLog { cygcheck -c cygwin } }
}

function Install-CygwinPackages {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if (-not ${PSCmdlet}.ShouldProcess("Cygwin", "Download setup and install packages")) { return }

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
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    Update-WinGetPackage "jqlang.jq"
    # New-SymLink -Source "${env:LOCALAPPDATA}\Microsoft\WinGet\Links\jq.exe"
    if (${PSCmdlet}.ShouldProcess("jq", "Create WinGet package command link")) {
        New-WinGetPackageLink -Id "jqlang.jq" -Command "jq"
    }
    if (-not ${WhatIfPreference}) { Import-Path }

    if (-not ${WhatIfPreference}) { Write-CommandLog { jq --version } }
}

function Install-Pester {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $command = '$ErrorActionPreference = "Stop"; Install-Module -Name Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck'

    if (${PSCmdlet}.ShouldProcess("powershell", "Install Pester 5 or later for the current user")) {
        Write-CommandLog { & powershell -NoProfile -Command $command } -IsDirectOutput $true
    }
    if (${PSCmdlet}.ShouldProcess("pwsh", "Install Pester 5 or later for the current user")) {
        Write-CommandLog { & pwsh -NoProfile -Command $command } -IsDirectOutput $true
    }
}

function Step6 {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Args)

    Write-Step 6 "Setup PowerShell"

    Update-PowerShell
    Update-PowerShellProfile
    Update-ExecutionPolicy

    if (${PSCmdlet}.ShouldProcess("${PROFILE}.CurrentUserAllHosts", "Load PowerShell profile")) {
        . ${PROFILE}.CurrentUserAllHosts
    }

    # Enable-DeveloperMode

    Update-Path -ForceFirst `
        "%USERPROFILE%\.local\bin" `
        "%LOCALAPPDATA%\Microsoft\WinGet\Links"

    if (-not ${WhatIfPreference}) {
        Write-CommandLog { Get-ChildItem "${env:APPDATA}\Microsoft\Windows\PowerShell\PSReadLine" }
        Write-CommandLog { Get-PSReadLineOption }
        Write-CommandLog { Get-PSReadLineKeyHandler }
    }

    Install-BusyBox
    # Install-Cygwin
    # Install-CygwinPackages
    Install-Jq
    Install-Pester
}

if ((-not ${MyInvocation}.ScriptName) -or (${MyInvocation}.ScriptName -ne "${PSCommandPath}")) {
    Import-Module -Name "$(Join-Path ("${PSCommandPath}" | Split-Path | Split-Path) "windows_utils.psm1")" -Force
    Step6 @PSBoundParameters
}
