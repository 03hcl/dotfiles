Import-Module -Name "$(Join-Path "${PSScriptRoot}" "windows.ps1")" -Force

function Get-TempDir { return Join-Path "${env:TEMP}" ".dotfiles-init" }

function Invoke-WithoutProgress ([ScriptBlock]$Script) {
    $pref = "${ProgressPreference}"
    $ProgressPreference = "SilentlyContinue"

    & ${Script}

    $ProgressPreference = "${pref}"
}

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

function Copy-Resource ([string]$Source, [string]$Target, [string]$TargetDir, [string]$TargetName = "${Source}") {
    $sourcePath = "$(Join-Path (Split-Path "$((Get-PSCallStack)[1].ScriptName)") "${Source}")"

    Write-Log "Copy '${Source}' ..."

    $dst = Initialize-ResourceDir "${sourcePath}" "${Target}" "${TargetDir}" "${TargetName}"

    try { Copy-Item -LiteralPath "${sourcePath}" -Destination "${dst}" -Force -ErrorAction Stop }
    catch { [System.IO.File]::WriteAllBytes("${dst}", [System.IO.File]::ReadAllBytes("${sourcePath}")) }

    Write-Log " -> Copied."
    return "${dst}"
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

function Invoke-ProcessCapture {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$FilePath,

        [Parameter(Position=1, ValueFromRemainingArguments=$true)]
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
        Out = "${outText}" -split "`r?`n";
        Err = "${errText}" -split "`r?`n";
        ExitCode = ${proc}.ExitCode;
    }
}

function Update-Path ([string]$append) {
    $expanded = [System.Environment]::ExpandEnvironmentVariables("${append}")
    if ("${expanded}" -in "${env:Path}".Split(';')) { return }

    $current = (Get-ItemProperty "HKCU:\Environment").Path
    [System.Environment]::SetEnvironmentVariable("Path", "${append};${current}", "User")

    Import-Path
}

function Update-EnvPath ([string]$key, [string]$value) {
    $current = (Get-ItemProperty "HKCU:\Environment")."${key}"
    foreach ($c in ${current}.Split(';')) {
        $expanded = [System.Environment]::ExpandEnvironmentVariables("${c}")
        if ("${expanded}" -eq "${value}") { return }
    }

    [System.Environment]::SetEnvironmentVariable("${key}", "${value};${current}", "User")
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
