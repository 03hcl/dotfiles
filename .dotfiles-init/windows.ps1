#!/usr/bin/env pwsh

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
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

function Write-CommandLog ([ScriptBlock]$Script, [bool]$IsDirectOutput = $false, [string]$Level = "INFO") {
    Write-Log ("-" * 72) "${Level}"
    Write-Log (" -> Command: ``$($Script.ToString().Trim())``") "${Level}"
    Write-Log ("-" * 72) "${Level}"

    if (${IsDirectOutput}) { & ${Script} }
    else { Write-Log (& ${Script} | Out-String) "${Level}" }
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

function Update-WinGetPackage([string]$Id, [string]$Source = "winget", [string]$Scope = "") {
    # $command = "winget list --source '${Source}' --id '${Id}'"
    # $installed = Write-CommandLog ([ScriptBlock]::Create($command)) -IsDirectOutput $true | Select-String '^[-]+$'

    # if (${installed}) { $subcommand = "upgrade" }
    # else { $subcommand = "install" }

    $command = "winget install --silent --exact --source '${Source}' --id '${Id}'"
    # $command = "winget ${subcommand} --silent --exact --source '${Source}' --id '${Id}'"
    if (${Scope}) { $command += " --scope ${Scope}" }

    Write-CommandLog ([ScriptBlock]::Create(${command})) -IsDirectOutput $true
}

function Step2 {
    Write-Step 2 "Install Latest Git Client"

    Update-WinGetPackage "Git.Git"
    Import-Path

    Write-CommandLog { git --version }
}

function Update-LocalRepo ([string]$Remote, [string]$Local, [string]$Origin, [string]$Branch) {
    if (-not (Test-Path -LiteralPath "$(Join-Path "${Local}" ".git")")) { return $false }
    if ((git -C "${Local}" remote get-url "${Origin}") -ne "${Remote}") { return $false }

    $actualBranch = git -C "${Local}" branch -vv | Where-Object { $_.Contains("[${Origin}/${Branch}]") }
    if (${actualBranch}) {
        if (${actualBranch} -isnot [string]) { return $false }
        if ((${actualBranch} -split "[\s\*]+")[1] -ne "${Branch}") { return $false }
    }

    Write-Log " -> Update repository."

    git -C "${Local}" fetch "${Origin}" "${Branch}"
    git -C "${Local}" checkout --detach
    git -C "${Local}" branch --force "${Branch}" "${Origin}/${Branch}"
    git -C "${Local}" switch "${Branch}"

    return $true
}

function Backup-Directory ([string]$Source) {
    $target = Get-BackupPath "${Source}"

    Write-Log " -> Failed to update source directory. Backing up to target directory."
    Write-Log "        Source: '${Source}'"
    Write-Log "        Target: '${target}'"

    if (-not (Confirm-Action "Confirm backup?")) {
        Write-Log " -> Aborted." "ERROR"
        throw "Aborted by user."
    }

    if (Test-Path -LiteralPath "${target}") { throw "Backup target already exists." }

    Write-Log " -> Backup started."

    New-Item -Path "$(Split-Path "${target}")" -ItemType "Directory" -Force > $null
    Move-Item -LiteralPath "${Source}" -Destination "${target}"

    Write-Log " -> Backup completed."
}

function Backup-LocalRepo ([string]$Local) { Backup-Directory "${Local}" }

function Get-RemoteRepo ([string]$Remote, [string]$Local, [string]$Origin, [string]$Branch) {
    if (Test-Path -LiteralPath "${Local}") { return }
    Write-Log " -> Clone repository."
    git clone "${Remote}" "${Local}" --origin "${Origin}" --branch "${Branch}"
}

function Step3 ([string]$Remote, [string]$Local, [string]$Origin = "origin", [string]$Branch = "main") {
    Write-Step 3 "Clone 03hcl/dotfiles Repository"

    if (Test-Path -LiteralPath "${Local}") {
        $isUpdated = Update-LocalRepo "${Remote}" "${Local}" "${Origin}" "${Branch}"
        if (-not ${isUpdated}) { Backup-LocalRepo "${Local}" }
    }

    Get-RemoteRepo "${Remote}" "${Local}" "${Origin}" "${Branch}"
}

function Step4 ([string]$Local) {
    Write-Step 4 "Search Additional Steps"

    $steps = @(Get-ChildItem -LiteralPath (Join-Path "${Local}" ".dotfiles-init") -Filter "step*" -Directory | Sort-Object)

    if (${steps}) {
        Write-Log ($steps | Format-Table -AutoSize | Out-String)
        Write-Log (" -> Found $(${steps}.Count) additional steps.")
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
    Write-Log "Hello, Windows!"

    Remove-Variable -Name "DotfilesInitBackupDir" -Scope "Global" -ErrorAction "SilentlyContinue"

    $remoteRepoPath = "https://github.com/03hcl/dotfiles.git"
    $localRepoPath = Join-Path "${env:USERPROFILE}" ".dotfiles"

    Step1
    Step2
    Step3 "${remoteRepoPath}" "${localRepoPath}"
    Step4 "${localRepoPath}"

    Write-Log
    Write-Log ("=" * 72)
    Write-Log "Successfully completed!"
    Write-Log ("=" * 72)
}

if (-not ${MyInvocation}.ScriptName) { Initialize-Dotfiles -Args ${args} }
