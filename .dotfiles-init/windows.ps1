#!/usr/bin/env pwsh

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

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

function Write-Command-Log ([ScriptBlock]$Script, [bool]$DirectOutput = $false, [string]$Level = "INFO") {
    Write-Log ("-" * 72) "${Level}"
    Write-Log (" -> Command: ``{0}``" -f ${Script}.ToString().Trim()) "${Level}"
    Write-Log ("-" * 72) "${Level}"

    if (${DirectOutput}) { & ${Script} }
    else { Write-Log (& ${Script} | Out-String) "${Level}" }
}

function Step1 {
    Write-Step 1 "Show Environment Information"

    # Write-Command-Log { Get-ComputerInfo | Format-List }

    Write-Command-Log { $PSVersionTable | Format-Table }
    Write-Command-Log { Get-ExecutionPolicy }
    Write-Command-Log { chcp }

    # Write-Command-Log { Get-Command "winget" | Format-List }
    # Write-Command-Log { winget --info }
    Write-Command-Log { winget --version }
}

function Update-WinGetPackage([string]$Id, [string]$Source = "winget", [string]$Scope = "") {
    # $command = "winget list --source '${Source}' --id '${Id}'"
    # $installed = Write-Command-Log ([ScriptBlock]::Create($command)) -DirectOutput $true | Select-String '^[-]+$'

    # if (${installed}) { $subcommand = "upgrade" }
    # else { $subcommand = "install" }

    $command = "winget install --silent --exact --source '${Source}' --id '${Id}'"
    # $command = "winget ${subcommand} --silent --exact --source '${Source}' --id '${Id}'"
    if (${Scope}) { $command += " --scope ${Scope}" }

    Write-Command-Log ([ScriptBlock]::Create(${command})) -DirectOutput $true
}

function Step2 {
    Write-Step 2 "Install Latest Softwares (WinGet, Git Client)"

    # TODO: Update WinGet itself (<https://github.com/microsoft/winget-cli>)

    Update-WinGetPackage "Git.Git"
    Write-Command-Log { git --version }
}

function Update-LocalRepo ([string]$Remote, [string]$local, [string]$Origin, [string]$Branch) {
    if (-not (Test-Path "${Local}\.git")) { return $false }
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

function Backup-LocalRepo ([string]$src) {
    $dst = ("{0}-backup\{1:yyyyMMdd_HHmmss}\{2}" -f "${src}", (Get-Date), (Split-Path "${src}" -Leaf))

    Write-Log " -> Failed to update dotfiles repo. Backing up the directory."
    Write-Log "        Source: ``${src}``"
    Write-Log "        Target: ``${dst}``"
    $response = Read-Host "Confirm backup? [y/N]"

    if ($response -ine "y") {
        Write-Log " -> Aborted."
        throw "Aborted by user."
    }

    Write-Log " -> Backup started."

    New-Item (Split-Path "${dst}") -ItemType "Directory" -Force
    Move-Item "${src}" -Destination "${dst}" -Force

    Write-Log " -> Backup completed."
}

function Get-RemoteRepo ([string]$Remote, [string]$local, [string]$Origin = "origin", [string]$Branch = "feat/win11") {
    if (Test-Path "${Local}") { return }
    Write-Log " -> Clone repository."
    git clone "${Remote}" "${Local}" --origin "${Origin}" --branch "${Branch}"
}

function Step3 ([string]$Remote, [string]$Local, [string]$Origin = "origin", [string]$Branch = "feat/win11") {
    Write-Step 3 "Clone 03hcl/dotfiles Repository"

    if (Test-Path "${Local}") {
        $updated = Update-LocalRepo "${Remote}" "${Local}" "${Origin}" "${Branch}"
        if (-not ${updated}) { Backup-LocalRepo "${Local}" }
    }

    Get-RemoteRepo "${Remote}" "${Local}" "${Origin}" "${Branch}"
}

function Main {
    Write-Log "Hello, Windows!"

    $remoteRepoPath = "https://github.com/03hcl/dotfiles.git"
    $localRepoPath = "${HOME}\.dotfiles"

    Step1
    Step2
    Step3 "${remoteRepoPath}" "${localRepoPath}"

    Write-Log
    Write-Log ("=" * 72)
    Write-Log "Successfully completed!"
    Write-Log ("=" * 72)
}

if ((-not ${MyInvocation}.ScriptName) -or (${MyInvocation}.ScriptName -eq ${PSCommandPath})) {
    Main -Args $args
}
