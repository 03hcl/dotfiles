#!/usr/bin/env pwsh

[CmdletBinding()]
param([int]$MaxStep)

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Confirm-Action ([string]$Message) { return (Read-Host "${Message} [y/N]") -ieq "y" }

function Get-BackupPath ([string]$Source) {
    $src = [System.IO.Path]::GetFullPath("${Source}")

    $homeDir = "${env:USERPROFILE}".TrimEnd("\") + "\"
    $startsWithHomeDir = ${src}.StartsWith("${homeDir}", [System.StringComparison]::OrdinalIgnoreCase)

    if (${startsWithHomeDir}) { $rel = ${src}.Substring(${homeDir}.Length) }
    else { $rel = ${src} -replace "^([A-Za-z]):", '$1' }

    # NOTE: Global, because each step imports windows_utils.psm1 (and this script) again with `-Force`
    if (-not (Test-Path -LiteralPath "variable:global:DotfilesInitBackupDir")) {
        $date = Get-Date -Format "yyyyMMdd_HHmmss"
        # NOTE: `Join-Path a b c` syntax is not supported in PowerShell < 7.0
        $global:DotfilesInitBackupDir = Join-Path "${env:USERPROFILE}" ".orig"
        $global:DotfilesInitBackupDir = Join-Path "${global:DotfilesInitBackupDir}" "${date}_${PID}"
    }

    return Join-Path "${global:DotfilesInitBackupDir}" "${rel}"
}

function Import-Path {
    $env:Path = [System.Environment]::ExpandEnvironmentVariables(
        [System.Environment]::GetEnvironmentVariable("Path", "Machine") +
        ";" +
        [System.Environment]::GetEnvironmentVariable("Path", "User")
    )
}

function Write-Log ([string]$Message = "", [string]$Level = "INFO") {
    $level, $levelColor = switch (${Level}) {
        # NOTSET
        # TRACE
        "DEBUG"   { ("[DEBUG]     ", "Cyan") }
        "INFO"    { ("[INFO]      ", "Green") }
        "WARNING" { ("[WARNING]   ", "Yellow") }
        "ERROR"   { ("[ERROR]     ", "Red") }
        "FATAL"   { ("[FATAL]     ", "Magenta") }
    }
    $time, $timeColor = (("{0:yyyy-MM-dd HH:mm:ss.fff (K)}    " -f (Get-Date)), "DarkGray")

    foreach ($line in ${Message} -split "`n") {
        Write-Host "${time}" -ForegroundColor "${timeColor}" -NoNewline
        Write-Host "${level}" -ForegroundColor "${levelColor}" -NoNewline
        Write-Host "${line}".TrimEnd()
    }
}

function Write-Step ([int]$Step, [string]$Name) {
    Write-Log
    Write-Log ("=" * 72)
    Write-Log "Step ${Step}: ${Name}"
    Write-Log ("=" * 72)
    Write-Log
}

function Write-CommandLog {
    param(
        [ScriptBlock]$Script,
        [bool]$IsDirectOutput = $false,
        [string]$Level = "INFO",
        [int[]]$SuccessExitCodes = @(0)
    )

    Write-Log ("-" * 72) "${Level}"
    Write-Log (" -> Command: ``$($Script.ToString().Trim())``") "${Level}"
    Write-Log ("-" * 72) "${Level}"

    # NOTE: Native commands set the global exit code; a local variable would hide it.
    $global:LASTEXITCODE = 0

    if (${IsDirectOutput}) { & ${Script} }
    else { Write-Log (& ${Script} | Out-String) "${Level}" }

    if ($SuccessExitCodes -notcontains ${global:LASTEXITCODE}) {
        throw "Command failed (exit code: ${global:LASTEXITCODE}): $($Script.ToString().Trim())"
    }
}

function Step1 {
    Write-Step 1 "Show Environment Information"

    # Write-CommandLog { Get-ComputerInfo | Format-List }

    Write-CommandLog { $PSVersionTable | Format-Table }
    Write-CommandLog { Get-ExecutionPolicy }
    Write-CommandLog { chcp }

    Write-CommandLog { Get-ChildItem "env:" }

    # Write-CommandLog { Get-Command "winget" | Format-List }
    # Write-CommandLog { winget --info }
    Write-CommandLog { winget --version }
}

function Update-WinGetPackage {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$Id, [string]$Source = "winget", [string]$Scope = "")

    # NOTE: Module functions need the caller's session state to inherit preference variables.
    if (-not $PSBoundParameters.ContainsKey("WhatIf")) {
        $WhatIfPreference = $PSCmdlet.SessionState.PSVariable.GetValue("WhatIfPreference", $false)
    }
    if (-not $PSBoundParameters.ContainsKey("Confirm")) {
        $ConfirmPreference = $PSCmdlet.SessionState.PSVariable.GetValue("ConfirmPreference", [System.Management.Automation.ConfirmImpact]::High)
    }

    # $command = "winget list --source '${Source}' --id '${Id}'"
    # $installed = Write-CommandLog ([ScriptBlock]::Create($command)) -IsDirectOutput $true | Select-String '^[-]+$'

    # if (${installed}) { $subcommand = "upgrade" }
    # else { $subcommand = "install" }

    $command = "winget install --silent --exact --source '${Source}' --id '${Id}'"
    # $command = "winget ${subcommand} --silent --exact --source '${Source}' --id '${Id}'"
    if (${Scope}) { $command += " --scope ${Scope}" }

    if (${PSCmdlet}.ShouldProcess("${Id}", "${command}")) {
        Write-CommandLog ([ScriptBlock]::Create(${command})) -IsDirectOutput $true -SuccessExitCodes @(0, -1978335189)
    }
}

function Step2 {
    Write-Step 2 "Install Latest Git Client"

    Update-WinGetPackage "Git.Git"
    Import-Path

    Write-CommandLog { git --version }
}

function Backup-File ([string]$Source, [string]$Target) {
    Write-Log " -> Back up existing file."
    Write-Log "        Source: '${Source}'"
    Write-Log "        Target: '${Target}'"

    if (-not (Confirm-Action "Confirm backup?")) {
        Write-Log " -> Aborted." "ERROR"
        throw "Aborted by user."
    }

    if (Test-Path -LiteralPath "${Target}") { throw "Backup target already exists." }

    New-Item -Path "$(Split-Path "${Target}")" -ItemType "Directory" -Force > $null
    Move-Item -LiteralPath "${Source}" -Destination "${Target}"
}

function Initialize-LocalRepo {
    param(
        [string]$LocalRepo = "${env:USERPROFILE}",
        [string]$RemoteRepo,
        [string]$Origin,
        [string]$Branch
    )
    $gitArgs = @("-C", "${LocalRepo}")
    $gitDir = Join-Path "${LocalRepo}" ".git"

    if (-not (Test-Path -LiteralPath "${gitDir}")) {
        Write-Log " -> Initialize repository."
        Write-CommandLog { git @gitArgs init "--initial-branch=${Branch}" }
        Write-CommandLog { git @gitArgs remote add "${Origin}" "${RemoteRepo}" }
    }

    $gitItem = Get-Item -LiteralPath "${gitDir}" -Force -ErrorAction "SilentlyContinue"
    if (
        (-not ${gitItem}) `
        -or (-not ${gitItem}.PSIsContainer) `
        -or (${gitItem}.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
    ) {
        Write-Log " -> Unexpected '.git'. Expected a directory, not a symbolic link." "ERROR"
        Write-Log "        Path:     ${gitDir}" "ERROR"
        throw "Unexpected .git directory."
    }

    $actualRemoteRepo = Write-CommandLog { git @gitArgs remote get-url "${Origin}" } -IsDirectOutput $true
    if ("${actualRemoteRepo}" -ne "${RemoteRepo}") {
        Write-Log " -> Unexpected remote URL." "ERROR"
        Write-Log "        Actual:   ${actualRemoteRepo}" "ERROR"
        Write-Log "        Expected: ${RemoteRepo}" "ERROR"
        throw "Unexpected remote URL."
    }

    Write-Log " -> Fetch repository."
    Write-CommandLog { git @gitArgs fetch "${Origin}" "${Branch}" }

    Write-CommandLog { git @gitArgs rev-parse --verify HEAD } -SuccessExitCodes @(0, 128)

    if ($global:LASTEXITCODE -eq 128) {
        Write-Log " -> Checkout repository."
        Write-CommandLog { git @gitArgs read-tree FETCH_HEAD }
        Write-CommandLog { git @gitArgs update-index -q --refresh }

        $files = Write-CommandLog { git @gitArgs -c core.quotePath=false ls-files --modified } -IsDirectOutput $true
        $localRoot = [System.IO.Path]::GetFullPath("${LocalRepo}").TrimEnd("\")
        foreach ($file in ${files}) {
            if (-not "${file}") { continue }

            $source = Join-Path "${LocalRepo}" "${file}"
            if (-not (Test-Path -LiteralPath "${source}")) { continue }

            $parent = Split-Path "${source}" -Parent
            while (${parent} -and (-not ${parent}.Equals("${localRoot}", [System.StringComparison]::OrdinalIgnoreCase))) {
                $parentItem = Get-Item -LiteralPath "${parent}" -Force
                if ($parentItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                    Write-Log " -> Unexpected symbolic link in the parent directories." "ERROR"
                    Write-Log "        Path:     ${parent}" "ERROR"
                    throw "Unexpected symbolic link in a parent directory."
                }
                $parent = Split-Path "${parent}" -Parent
            }

            Backup-File "${source}" (Get-BackupPath "${source}")
        }

        Write-CommandLog { git @gitArgs checkout-index -a }
        Write-CommandLog { git @gitArgs symbolic-ref HEAD "refs/heads/${Branch}" }
        Write-CommandLog { git @gitArgs update-ref "refs/heads/${Branch}" FETCH_HEAD }
        Write-CommandLog { git @gitArgs branch "--set-upstream-to=${Origin}/${Branch}" "${Branch}" }
        Write-CommandLog { git @gitArgs remote set-head "${Origin}" "${Branch}" }
    }
    else {
        Write-Log " -> Update repository."
        $remoteHead = Write-CommandLog { git @gitArgs rev-parse --verify "FETCH_HEAD^{commit}" } -IsDirectOutput $true

        Write-CommandLog { git @gitArgs merge-base --is-ancestor "${remoteHead}" HEAD } -SuccessExitCodes @(0, 1)
        if ($global:LASTEXITCODE -eq 0) { return }

        $actualBranch = Write-CommandLog { git @gitArgs branch --show-current } -IsDirectOutput $true
        if ("${actualBranch}" -ne "${Branch}") {
            Write-Log " -> Unexpected current branch." "ERROR"
            Write-Log "        Actual:   ${actualBranch}" "ERROR"
            Write-Log "        Expected: ${Branch}" "ERROR"
            throw "Unexpected current branch."
        }

        if (Write-CommandLog { git @gitArgs status --porcelain --untracked-files=no } -IsDirectOutput $true) {
            Write-Log " -> Uncommitted changes exist. Commit or stash them first." "ERROR"
            throw "Uncommitted changes exist."
        }

        Write-CommandLog { git @gitArgs merge --ff-only --no-overwrite-ignore "${remoteHead}" }
    }
}

function Step3 ([string]$RemoteRepo, [string]$Origin = "origin", [string]$Branch = "main") {
    Write-Step 3 "Initialize or Update 03hcl/dotfiles Repository"
    Initialize-LocalRepo -RemoteRepo "${RemoteRepo}" -Origin "${Origin}" -Branch "${Branch}"
}

function Step4 ([string]$Local, [int]$MaxStep) {
    Write-Step 4 "Search Additional Steps"

    $steps = @(
        Get-ChildItem -LiteralPath (Join-Path "${Local}" ".dotfiles-init") -Filter "step*" -Directory `
        | Where-Object { ($_.Name -match "^step(\d+)") -and ([int]$Matches[1] -le ${MaxStep}) } `
        | Sort-Object
    )

    if (${steps}) {
        Write-Log ($steps | Format-Table -AutoSize | Out-String)
        Write-Log (" -> Found $(${steps}.Count) additional steps to run.")
        Set-ExecutionPolicy -ExecutionPolicy "RemoteSigned" -Scope "Process"
    }
    else { Write-Log " -> No additional steps found." }

    foreach ($step in ${steps}) {
        $file = Join-Path ${step}.FullName "windows.ps1"
        if (-not (Test-Path -LiteralPath "${file}")) { continue }
        . ${file}
    }
}

function Initialize-Dotfiles {
    param(
        [ValidateRange(1, 2147483647)]
        [int]$MaxStep = $(
            if ($env:DOTFILES_INIT_MAX_STEP) { $env:DOTFILES_INIT_MAX_STEP }
            else { [int]::MaxValue }
        )
    )

    Write-Log "Hello, Windows!"

    Remove-Variable -Name "DotfilesInitBackupDir" -Scope "Global" -ErrorAction "SilentlyContinue"

    $remoteRepoPath = "https://github.com/03hcl/dotfiles.git"

    if (${MaxStep} -ge 1) { Step1 }
    if (${MaxStep} -ge 2) { Step2 }
    if (${MaxStep} -ge 3) { Step3 "${remoteRepoPath}" }
    if (${MaxStep} -ge 4) { Step4 "${env:USERPROFILE}" ${MaxStep} }

    Write-Log
    Write-Log ("=" * 72)
    Write-Log "Successfully completed!"
    Write-Log ("=" * 72)
}

if (-not ${MyInvocation}.ScriptName) { Initialize-Dotfiles @PSBoundParameters }
