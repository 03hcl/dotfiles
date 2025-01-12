Import-Module -Name "$(Join-Path "${PSScriptRoot}" "windows.ps1")" -Force

function Invoke-WithoutProgress ([ScriptBlock]$Script)
{
    $pref = "${ProgressPreference}"
    $ProgressPreference = "SilentlyContinue"

    & ${Script}

    $ProgressPreference = "${pref}"
}

function Copy-Resource ([string]$Source, [string]$Target, [string]$TargetDir, [string]$TargetName = "${Source}") {
    $sourcePath = "$(Join-Path (Split-Path "$((Get-PSCallStack)[1].ScriptName)") "${Source}")"

    if ("${Target}") {
        $TargetDir = "$(Split-Path "${Target}")"
        $TargetName = "$(Split-Path "${Target}" -Leaf)"
    }
    else { $Target = "$(Join-Path "${TargetDir}" "${TargetName}")" }

    Write-Log "Copy '${Source}' ..."
    Write-Log "    from:   ${sourcePath}"
    Write-Log "    to:     ${Target}"

    if ("${TargetDir}" -and (-not (Test-Path "${TargetDir}"))) {
        New-Item -Path "${TargetDir}" -ItemType "Directory" -Force > $null
    }
    Copy-Item -Path "${sourcePath}" -Destination "${Target}" -Force
    # Copy-Item -Path origin.txt -Destination copied.txt

    Write-Log " -> Copied."
}

function Update-Path ([string]$append) {
    $expanded = [System.Environment]::ExpandEnvironmentVariables("${append}")
    if ("${expanded}" -in "${env:Path}".Split(';')) { return }

    $current = (Get-ItemProperty "HKCU:\Environment").Path
    [System.Environment]::SetEnvironmentVariable("Path", "${append};${current}", "User")

    Import-Path
}

function New-SymLink {
    param (
        [string]$Source,
        [string]$Target,
        [string]$TargetDir = "${env:USERPROFILE}\.local\bin",
        [string]$TargetName = "$(Split-Path "${Source}" -Leaf)"
    )

    if ("${Target}") {
        $TargetDir = "$(Split-Path "${Target}")"
        $TargetName = "$(Split-Path "${Target}" -Leaf)"
    }
    else { $Target = "$(Join-Path "${TargetDir}" "${TargetName}")" }

    Write-Log "Create a symbolic link of '$(Split-Path "${Source}" -Leaf)' ..."
    Write-Log "    from:   ${Source}"
    Write-Log "    to:     ${Target}"

    if (Test-Path "${Target}") {
        $prop = Get-ItemProperty "${Target}"

        # NOTE: `.LinkTarget` is probably not supported in PowerShell < 7.1
        # if (${prop} -and (${prop}.LinkTarget -eq "${Source}")) {
        if (${prop} -and (${prop}.Target -eq "${Source}")) {
            Write-Log " -> Already exists."
            return
        }
    }

    New-Item -Path "${TargetDir}" -ItemType "Directory" -Force > $null

    # NOTE: Not working on PowerShell 5.1 even with developer mode
    # New-Item -Path "${Target}" -Value "${Source}" -ItemType "SymbolicLink" -Force
    Start-Process pwsh -Verb "RunAs" -Wait -ArgumentList @(
        "-NoProfile",
        "-Command",
        "New-Item -Path '${Target}' -Value '${Source}' -ItemType 'SymbolicLink' -Force"
    )

    Write-Log " -> Created."
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
    if (-not "${TargetDir}") { $TargetDir = "${env:TEMP}" }

    Write-Log "Fetch latest tag of ${Owner}/${Repo} ..."

    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/${Owner}/${Repo}/releases/latest" -UseBasicParsing

    Write-Log
    Write-Log " -> Tag: $(${release}.tag_name)"
    Write-Log "    URL: $(${release}.html_url)"
    Write-Log

    $asset = ${release}.assets | Where-Object { $_.name -eq "${AssetName}" }
    $source = ${asset}.browser_download_url
    $target = "${TargetDir}/${AssetName}"

    Write-Log "Download an asset ..."
    Write-Log
    Write-Log "    from:   ${source}"
    Write-Log "    to:     ${target}"

    Invoke-WithoutProgress { Invoke-WebRequest -Uri "${source}" -OutFile "${target}" }

    Write-Log
    Write-Log " -> Downloaded."
    return "${target}"
}
