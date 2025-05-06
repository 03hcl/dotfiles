#!/usr/bin/env pwsh

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Reference: https://git-scm.com/docs/git-var
function Get-GitVariables ([string]$Var) {
    return git var "${Var}" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

function Remove-GitPaths ([string[]]$Paths) {
    # Write-Log "Reset config files"
    # Write-Log

    foreach ($path in ${Paths}) {
        Write-Log "Path:   ${path}"
        if (Test-Path "${path}") {
            Remove-Item -Path "${path}" -Force
            Write-Log " -> Removed."
        }
        else { Write-Log " -> Not found." }
    }
}

function Set-GitConfig ([string]$Path) {
    New-Item -Path "${Path}" -Force > $null

    $gitArgs = @("config", "set", "--file", "${Path}")

    git @gitArgs user.name "03"
    git @gitArgs user.email "kntaco03g1@gmail.com"

    git @gitArgs core.autocrlf input
    git @gitArgs core.editor "code --wait"
    # git @gitArgs core.excludesfile "${env:USERPROFILE}\.config\git\ignore"
    git @gitArgs core.safecrlf true
    git @gitArgs init.defaultBranch main
    git @gitArgs rerere.enabled true
}

# Reference: https://git-scm.com/docs/git-config
function Update-GitConfig {
    $paths = @(Get-GitVariables GIT_CONFIG_GLOBAL)
    Remove-GitPaths -Paths $paths

    $path = $paths[0]
    Set-GitConfig -Path "${path}"

    Write-Log
    Write-CommandLog { git config list --global }
    # foreach ($p in ${paths}) {
    #     Write-Log ("-" * 72)
    #     Write-Log "`$p = `"${p}`""
    #     Write-CommandLog { git config list "--file" "${p}" }
    # }
}

# Reference: https://git-scm.com/docs/gitattributes
function Update-GitAttributes {
    $attrs = @(Get-GitVariables GIT_ATTR_GLOBAL)
    Remove-GitPaths -Paths $attrs

    Write-Log
    Copy-Resource -Source ".gitattributes" -Target $attrs[0]
}

# Reference: https://git-scm.com/docs/gitignore
function Update-GitIgnore {
    # Remove-GitPaths -Paths @("${env:USERPROFILE}\.config\git\ignore")

    # Write-Log
    Copy-Resource -Source ".gitignore_global" -Target "${env:USERPROFILE}\.config\git\ignore"
}

function Step5 {
    Write-Step 5 "Setup Git"

    Update-GitConfig

    Write-Log
    Write-Log ("-" * 72)
    Write-Log

    Update-GitAttributes

    Write-Log
    Write-Log ("-" * 72)
    Write-Log

    Update-GitIgnore
}

if ((-not ${MyInvocation}.ScriptName) -or (${MyInvocation}.ScriptName -ne "${PSCommandPath}")) {
    Import-Module -Name "$(Join-Path ("${PSCommandPath}" | Split-Path | Split-Path) "windows_utils.psm1")" -Force
    Step5 -Args $args
}
