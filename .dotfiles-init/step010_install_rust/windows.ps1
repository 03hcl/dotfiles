#!/usr/bin/env pwsh

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8


function Step10 {
    Write-Step 10 "Install Rust"

    $uri = "https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe"
    $file = "${env:TEMP}\rustup-init.exe"

    Invoke-WebRequest -Uri "${uri}" -OutFile "${file}"
    & "${file}" -y
    Update-Path "%USERPROFILE%\.cargo\bin"

    Write-CommandLog { rustup --version }

    rustup update

    Write-CommandLog { rustup --version }
    Write-CommandLog { rustc --version }
    Write-CommandLog { cargo --version }
    Write-CommandLog { cargo fmt --version }
    # Write-CommandLog { rustfmt --version }
    Write-CommandLog { cargo clippy --version }

    rustup component add rust-analyzer
    Write-CommandLog { rust-analyzer --version }

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
    cargo install --force cargo-script
    Write-CommandLog { cargo script --version }
    # Write-CommandLog { cargo-script --version }
    # Write-CommandLog { run-cargo-script --version }

    # Reference:
    #   https://crates.io/crates/cargo-audit
    #   https://github.com/RustSec/rustsec/tree/main/cargo-audit
    cargo install --force cargo-audit
    Write-CommandLog { cargo audit --version }

    # Reference:
    #   https://crates.io/crates/cargo-outdated
    #   https://github.com/kbknapp/cargo-outdated
    cargo install --force cargo-outdated
    Write-CommandLog { cargo outdated --version }
}

if ((-not ${MyInvocation}.ScriptName) -or (${MyInvocation}.ScriptName -ne "${PSCommandPath}")) {
    Import-Module -Name "$(Join-Path ("${PSCommandPath}" | Split-Path | Split-Path) "windows_utils.psm1")" -Force
    Step10 -Args $args
}
