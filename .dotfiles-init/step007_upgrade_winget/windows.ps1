#!/usr/bin/env pwsh

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Download-LatestGitHubAsset ([string]$Owner, [string]$Repo, [string]$AssetName, [string]$TargetDir = "${env:TEMP}") {
    Write-Log "Fetch latest tag of ${Owner}/${Repo} ..."
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/${Owner}/${Repo}/releases/latest" -UseBasicParsing
    Write-Log " -> Tag: $($release.tag_name) (URL: '$($release.html_url)')"

    $asset = $release.assets | Where-Object { $_.name -eq $AssetName }
    $source = $asset.browser_download_url
    $target = "${TargetDir}/${AssetName}"

    Write-Log
    Write-Log "Download an asset from '${source}' to '${target}' ,,,"    
    Invoke-WebRequest -Uri "${source}" -OutFile "${target}"
    Write-Log " -> Downloaded."
}

function Step7 {
    Write-Step 7 "Upgrade WinGet"

    # Download-LatestGitHubAsset -Owner "microsoft" -Repo "winget-cli" -AssetName "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    Download-LatestGitHubAsset -Owner "microsoft" -Repo "winget-cli" -AssetName "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.txt"

    # TODO: install
    # Import-Path

    # Write-Command-Log { winget --version }
}

if ((-not ${MyInvocation}.ScriptName) -or (${MyInvocation}.ScriptName -ne ${PSCommandPath})) {
    . (Join-Path (Split-Path (Split-Path ${PSCommandPath})) "windows.ps1")
    Step7 -Args $args
}
