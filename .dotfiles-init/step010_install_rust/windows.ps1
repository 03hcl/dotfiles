#!/usr/bin/env pwsh

[CmdletBinding(SupportsShouldProcess = $true)]
param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Args)

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Install-Rust {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $uri = "https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe"
    $file = "${env:TEMP}\rustup-init.exe"

    if (${PSCmdlet}.ShouldProcess("Rust toolchain", "Download rustup and install")) {
        Invoke-WebRequest -Uri "${uri}" -OutFile "${file}"
        $target = "x86_64-pc-windows-gnu"
        & "${file}" -y --default-host "${target}"  # --default-toolchain "stable-${target}"
        Update-Path "%USERPROFILE%\.cargo\bin"

        Write-CommandLog { rustup --version }
    }
}

function Update-Rust {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if (${PSCmdlet}.ShouldProcess("Rust toolchain", "Run rustup update")) { rustup update }

    if (-not ${WhatIfPreference}) {
        Write-CommandLog { rustup --version }
        Write-CommandLog { rustc --version }
        Write-CommandLog { cargo --version }
        Write-CommandLog { cargo fmt --version }
        # Write-CommandLog { rustfmt --version }
        Write-CommandLog { cargo clippy --version }
    }
}

# function Install-VSBuildTools {
#     $uri = "https://aka.ms/vs/17/release/vs_BuildTools.exe"
#     $file = "${env:TEMP}\vs_BuildTools.exe"

#     Invoke-WebRequest -Uri "${uri}" -OutFile "${file}"
#     Start-Process -NoNewWindow -Wait -FilePath "${file}"
# }

function Install-RustOfficialTools {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if (${PSCmdlet}.ShouldProcess("rust-analyzer", "Install rustup component")) {
        rustup component add rust-analyzer
    }
    if (-not ${WhatIfPreference}) { Write-CommandLog { rust-analyzer --version } }
}

function Install-RustUnofficialTools {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    # cargo install --force ...
    # 候補:
    #   cargo-edit
    #   cargo-expand
    #   cargo-watch
    #   cargo-script
    #   cargo-audit
    #   cargo-outdated
    #   cargo-tree
    #   cargo-benchcmp?
    #   cargo-license
    #   cargo-modules?
    #   cargo-update?
    #   cargo-build-deps?
    #   cargo-bisect-rustc?

    # Reference:
    #   https://crates.io/crates/cargo-script
    #   https://github.com/DanielKeep/cargo-script
    if (${PSCmdlet}.ShouldProcess("cargo-script", "Install Cargo package")) {
        cargo install --force cargo-script
    }
    if (-not ${WhatIfPreference}) { Write-CommandLog { cargo script --version } }
    # Write-CommandLog { cargo-script --version }
    # Write-CommandLog { run-cargo-script --version }

    # Reference:
    #   https://crates.io/crates/cargo-audit
    #   https://github.com/RustSec/rustsec/tree/main/cargo-audit
    if (${PSCmdlet}.ShouldProcess("cargo-audit", "Install Cargo package")) {
        cargo install --force cargo-audit
    }
    if (-not ${WhatIfPreference}) { Write-CommandLog { cargo audit --version } }

    # Reference:
    #   https://crates.io/crates/cargo-outdated
    #   https://github.com/kbknapp/cargo-outdated
    if (${PSCmdlet}.ShouldProcess("cargo-outdated", "Install Cargo package")) {
        cargo install --force cargo-outdated
    }
    if (-not ${WhatIfPreference}) { Write-CommandLog { cargo outdated --version } }
}

function Step10 {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Args)

    Write-Step 10 "Install Rust"

    Install-Rust
    Update-Rust

    Install-RustOfficialTools
    Install-RustUnofficialTools
}

if ((-not ${MyInvocation}.ScriptName) -or (${MyInvocation}.ScriptName -ne "${PSCommandPath}")) {
    Import-Module -Name "$(Join-Path ("${PSCommandPath}" | Split-Path | Split-Path) "windows_utils.psm1")" -Force
    Step10 @PSBoundParameters
}
