#!/usr/bin/env pwsh

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Reference: https://git-scm.com/docs/git-var
function Get-GitVariables ([string]$Var) {
    $res = Invoke-ProcessCapture git "var" "${Var}"

    if (${res}.ExitCode -eq 0) { return ${res}.Out | ForEach-Object { "$_".Trim() } | Where-Object { $_ } }

    foreach ($l in ${res}.Err) { Write-Log "${l}" "ERROR" }

    $path = $null
    foreach ($l in ${res}.Err) { if ($l -match '(?i)(?<p>[A-Za-z]:[\\/][^\s''"]+)') { $path = ${Matches}['p'] } }
    if (-not ${path}) { return @() }

    $locked = Get-LockingProcesses -Path $path
    if (-not ${locked}) { return @() }

    foreach ($p in $locked) { Write-Log " -> Probably locked by PID: $($p.ProcessId) ($($p.Name))" "ERROR" }
    return @()
}

function Remove-GitPaths ([string[]]$Paths) {
    if (-not ${Paths}) { return }

    $path = ${Paths}[0]
    Write-Log "Path:   '${path}'"
    if (Test-Path "${path}") {
        # TODO: backup
        Remove-Item -Path "${path}" -Force -ErrorAction Stop
        Write-Log " -> Removed."
    }
    else { Write-Log " -> Not found." }

    if (${Paths}.Count -eq 1) { return }

    foreach ($path in ${Paths}[1..(${Paths}.Count - 1)]) {
        Write-Log "Path:   '${path}'"
        if (Test-Path "${path}") { Write-Log " -> Already exists." }
        else {
            New-Item -Path "${path}" -Force > $null
            Write-Log " -> Created."
        }
    }
}

function Set-GitConfig ([string]$Path) {
    Write-Log "Path:   '${Path}'"
    New-Item -Path "${Path}" -Force > $null
    Write-Log " -> Created."

    $gitArgs = @("config", "set", "--file", "${Path}")

    git @gitArgs user.email             "kntaco03g1@gmail.com"
    git @gitArgs user.name              "03"

    git @gitArgs core.autocrlf          input
    git @gitArgs core.editor            "code --wait"
    # git @gitArgs core.excludesfile      "${env:USERPROFILE}\.config\git\ignore"
    git @gitArgs core.safecrlf          true

    git @gitArgs init.defaultbranch     main

    git @gitArgs rerere.enabled         true
}

# Reference: https://git-scm.com/docs/git-config
function Update-GitConfig {
    $paths = @(Get-GitVariables GIT_CONFIG_GLOBAL)
    if (${paths}.Count -eq 0) { Write-Log "" "ERROR"; Write-Log " -> Not found global config path." "ERROR" }

    Remove-GitPaths -Paths $paths
    Write-Log

    $path = $paths[0]
    Set-GitConfig -Path "${path}"
    Write-Log

    Write-CommandLog { git config list --show-origin --show-scope | Where-Object { $_ -match '^(system|global)\s' } }
}

# Reference: https://git-scm.com/docs/gitattributes
function Update-GitAttributes {
    $paths = @(Get-GitVariables GIT_ATTR_GLOBAL)
    if (${paths}.Count -eq 0) { Write-Log "" "ERROR"; Write-Log " -> Not found global attributes path." "ERROR" }

    Remove-GitPaths -Paths ${paths}
    Write-Log

    Copy-Resource -Source ".gitattributes" -Target ${paths}[0] > $null
}

# Reference: https://git-scm.com/docs/gitignore
function Update-GitIgnore {
    # TODO: Get from git config
    $paths = @("${env:USERPROFILE}\.config\git\ignore")

    Remove-GitPaths -Paths ${paths}
    Write-Log

    Copy-Resource -Source ".gitignore_global" -Target ${paths}[0] > $null
}

function Step5 {
    Write-Step 5 "Setup Git"

    Update-GitConfig

    # Write-Log
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
