Import-Module -Name "$(Join-Path "${PSScriptRoot}" "windows.ps1")" -Force

function Copy-Resource ([string]$Source, [string]$Target, [string]$TargetDir, [string]$TargetName = "${Source}") {
    $sourcePath = "$(Join-Path (Split-Path "$((Get-PSCallStack)[1].ScriptName)") "${Source}")"

    Write-Log "Copy '${Source}' ..."

    $dst = Initialize-ResourceDir "${sourcePath}" "${Target}" "${TargetDir}" "${TargetName}"

    try { Copy-Item -LiteralPath "${sourcePath}" -Destination "${dst}" -Force -ErrorAction Stop }
    catch { [System.IO.File]::WriteAllBytes("${dst}", [System.IO.File]::ReadAllBytes("${sourcePath}")) }

    Write-Log " -> Copied."
    return "${dst}"
}

function Expand-Env ([string]$Name) { [System.Environment]::ExpandEnvironmentVariables("${Name}") }

function Get-LatestGitHubAsset ([string]$Owner, [string]$Repo, [string]$AssetName, [string]$TargetDir) {
    if (-not "${TargetDir}") { $TargetDir = "$(Get-TempDir)\${Repo}" }

    Write-Log "Fetch latest tag of '${Owner}/${Repo}' ..."

    $apiUri = "https://api.github.com/repos/${Owner}/${Repo}/releases/latest"
    $release = Invoke-RestMethod -Uri "${apiUri}" -UseBasicParsing

    Write-Log
    Write-Log " -> Tag: '$(${release}.tag_name)'"
    Write-Log "    URL: '$(${release}.html_url)'"
    Write-Log

    $asset = ${release}.assets | Where-Object { $_.name -eq "${AssetName}" }
    $source = ${asset}.browser_download_url
    $target = "${TargetDir}/${AssetName}"

    Write-Log "Download an asset ..."
    Write-Log
    Write-Log "    from:   '${source}'"
    Write-Log "    to:     '${target}'"

    Invoke-WithoutProgress { Invoke-WebRequest -Uri "${source}" -OutFile "${target}" }

    Write-Log
    Write-Log " -> Downloaded."
    return "${target}"
}

function Get-LockingProcesses ([string]$Path) {
    $name = [System.IO.Path]::GetFileName("${Path}")
    return Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and ($_.CommandLine -like "*${name}*") }
}

function Get-OnlineResource {
    param (
        [string]$Source,
        [string]$Target,
        [string]$TargetDir = "$(Get-TempDir)",
        [string]$TargetName = "$(Split-Path "${Source}" -Leaf)"
    )

    Write-Log "Download '${Source}' ..."

    $dst = Initialize-ResourceDir "${Source}" "${Target}" "${TargetDir}" "${TargetName}"
    Invoke-WithoutProgress { Invoke-WebRequest -Uri "${Source}" -OutFile "${dst}" }

    Write-Log " -> Downloaded."
    return "${dst}"
}

function Get-CommonParameters {
    param([Parameter(Mandatory = $true, Position = 0)][hashtable]$Params)

    # Reference:
    #   https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_commonparameters
    #   https://learn.microsoft.com/ja-jp/powershell/scripting/learn/deep-dives/everything-about-shouldprocess
    $allowed = @(
        "ActionPreference",
        "Confirm",
        "Debug",
        "ErrorAction",
        "ErrorVariable",
        "InformationAction",
        "InformationVariable",
        "OutBuffer",
        "OutVariable",
        "PipelineVariable",
        "ProcessAction",
        "Verbose",
        "WarningAction",
        "WarningVariable",
        "WhatIf"
    )

    return $Params.GetEnumerator() |
        Where-Object { ${allowed} -contains $_.Key } |
        ForEach-Object -Begin { $result = @{} } -Process { ${result}[$_.Key] = $_.Value } -End { ${result} }
}

function Get-RawRegistryValue ([string]$Path, [string]$Name) {
    $sub = ${Path} -replace "^.+?:[/\\]", ""

    if (${Path} -like "HKLM:*") { $client = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(${sub}) }
    else { $client = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(${sub}) }

    if (-not ${client}) { return $null }

    return ${client}.GetValue(${Name}, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
}

function Get-TempDir { return Join-Path "${env:TEMP}" ".dotfiles-init" }

function Initialize-ResourceDir ([string]$Source, [string]$Target, [string]$TargetDir, [string]$TargetName) {
    if ("${Target}") {
        $TargetDir = "$(Split-Path "${Target}")"
        $TargetName = "$(Split-Path "${Target}" -Leaf)"
    }
    else { $Target = "$(Join-Path "${TargetDir}" "${TargetName}")" }

    Write-Log "    from:   '${Source}'"
    Write-Log "    to:     '${Target}'"

    if ("${TargetDir}" -and (-not (Test-Path "${TargetDir}"))) {
        New-Item -Path "${TargetDir}" -ItemType "Directory" -Force > $null
    }

    return "${Target}"
}

function Invoke-ProcessCapture {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$FilePath,

        [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
        [string[]]$ArgumentList
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo

    ${psi}.FileName = ${FilePath}
    ${psi}.Arguments = (${ArgumentList} | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '

    ${psi}.CreateNoWindow = $true
    ${psi}.RedirectStandardError = $true
    ${psi}.RedirectStandardOutput = $true
    ${psi}.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    ${psi}.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    ${psi}.UseShellExecute = $false

    $proc = New-Object System.Diagnostics.Process
    ${proc}.StartInfo = ${psi}

    ${proc}.Start() > $null
    $outText = ${proc}.StandardOutput.ReadToEnd()
    $errText = ${proc}.StandardError.ReadToEnd()
    ${proc}.WaitForExit()

    return [PSCustomObject]@{
        Out      = "${outText}" -split "`r?`n";
        Err      = "${errText}" -split "`r?`n";
        ExitCode = ${proc}.ExitCode;
    }
}

function Invoke-WithoutProgress ([ScriptBlock]$Script) {
    $pref = "${ProgressPreference}"
    $ProgressPreference = "SilentlyContinue"

    & ${Script}

    $ProgressPreference = "${pref}"
}

function New-SymLink {
    param (
        [string]$Source,
        [string]$Target,
        [string]$TargetDir = "${env:USERPROFILE}\.local\bin",
        [string]$TargetName = "$(Split-Path "${Source}" -Leaf)"
    )

    Write-Log "Create a symbolic link of '$(Split-Path "${Source}" -Leaf)' ..."

    $dst = Initialize-ResourceDir "${Source}" "${Target}" "${TargetDir}" "${TargetName}"

    if (Test-Path "${dst}") {
        $prop = Get-ItemProperty "${dst}"

        # NOTE: `.LinkTarget` is probably not supported in PowerShell < 7.1
        # if (${prop} -and (${prop}.LinkTarget -eq "${Source}")) {
        if (${prop} -and (${prop}.Target -eq "${Source}")) {
            Write-Log " -> Already exists."
            return
        }
    }

    # NOTE: Not working on PowerShell 5.1 even with developer mode
    # New-Item -Path "${dst}" -Value "${Source}" -ItemType "SymbolicLink" -Force
    Start-Process -FilePath "pwsh.exe" -Verb "RunAs" -Wait -ArgumentList @(
        "-NoProfile",
        "-Command",
        "New-Item -Path '${dst}' -Value '${Source}' -ItemType 'SymbolicLink' -Force"
    )

    Write-Log " -> Created."
    return "${dst}"
}

function New-WinGetPackageLink {
    param (
        [string]$Id,
        [string]$Command,
        [string]$WinGetSource = "Microsoft.Winget.Source",
        [string]$PublisherId = "8wekyb3d8bbwe"
    )
    $sourceDir = "${env:LOCALAPPDATA}\Microsoft\WinGet\Packages\${Id}_${WinGetSource}_${PublisherId}"
    New-SymLink -Source "${sourceDir}\${Command}.exe"
}

function Update-Path {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [switch]$ForceFirst = $false,
        [string]$Path = "HKCU:\Environment",
        [string]$Key = "Path",

        [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Values
    )

    $valid = ${Values} | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    if (${valid}) { [array]::Reverse(${valid}) }

    foreach ($target in ${valid}) {
        $current = (Get-RawRegistryValue "${Path}" "${Key}") -split ';' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
        $new = ${current}
        $expandedTarget = Expand-Env ${target}

        if (${expandedTarget} -in (${current} | ForEach-Object { Expand-Env $_ })) {
            if (-not ${ForceFirst}) { continue }
            $new = ${new} | Where-Object { (Expand-Env $_) -ne ${expandedTarget} }
        }

        $value = (@(${target}) + ${new}) -join ';'

        $message = "Set Key: '${Key}' to Value: '${value}'"
        if (-not ${PSCmdlet}.ShouldProcess("${Path}", "${message}")) { continue }

        [System.Environment]::SetEnvironmentVariable("${Key}", "${value}", "User")
        if ("${Key}" -eq "Path") { Import-Path }
    }
}
