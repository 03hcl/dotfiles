#!/usr/bin/env pwsh

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

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
    New-Item (Split-Path "${Path}") -ItemType "Directory" -Force
    New-Item -Path "${Path}"

    $gitArgs = @("config", "set", "--file", "${Path}")

    git @gitArgs user.name "03"
    git @gitArgs user.email "kntaco03g1@gmail.com"

    git @gitArgs core.autocrlf input
    git @gitArgs core.editor "code --wait"
    # git @gitArgs core.excludesfile "${env:UserProfile}\.config\git\ignore"
    git @gitArgs core.safecrlf true
    git @gitArgs init.defaultBranch main
    git @gitArgs rerere.enabled true
}

function Update-GitConfig {
    $paths = @(Get-GitVariables GIT_CONFIG_GLOBAL)
    Remove-GitPaths -Paths $paths

    $path = $paths[0]
    Set-GitConfig -Path "${path}"

    Write-Log
    Write-Command-Log { git config list --global }
    # foreach ($p in ${paths}) {
    #     Write-Log ("-" * 72)
    #     Write-Log "`$p = `"${p}`""
    #     Write-Command-Log { git config list "--file" "${p}" }
    # }
}

function Update-GitAttributes {
    $attrs = @(Get-GitVariables GIT_ATTR_GLOBAL)

    Remove-GitPaths -Paths $attrs

    $source = "$(Join-Path (Split-Path "${PSCommandPath}") ".gitattributes")"
    $target = $attrs[0]

    Write-Log
    Write-Log "Copy '.gitattributes' ..."
    Write-Log "    from:   ${source}"
    Write-Log "    to:     ${target}"

    Copy-Item -Path "${source}" -Destination "${target}"

    Write-Log " -> Copied."
}

function Update-GitIgnore {
    $target = "${env:UserProfile}\.config\git\ignore"
    Write-Log
    Remove-GitPaths -Paths @($target)

    $source = "$(Join-Path (Split-Path "${PSCommandPath}") ".gitignore_global")"

    Write-Log
    Write-Log "Copy '.gitignore_global' ..."
    Write-Log "    from:   ${source}"
    Write-Log "    to:     ${target}"

    Copy-Item -Path "${source}" -Destination "${target}"

    Write-Log " -> Copied."
}

function Step5 {
    Write-Step 5 "Setup Git Config"

    Update-GitConfig
    Update-GitAttributes
    Update-GitIgnore
}

if ((-not ${MyInvocation}.ScriptName) -or (${MyInvocation}.ScriptName -ne ${PSCommandPath})) {
    . (Join-Path (Split-Path (Split-Path ${PSCommandPath})) "windows.ps1")
    Step5 -Args $args
}
