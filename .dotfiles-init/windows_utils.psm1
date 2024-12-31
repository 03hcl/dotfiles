Import-Module -Name "$(Join-Path "${PSScriptRoot}" "windows.ps1")" -Force

function Invoke-WithoutProgress ([ScriptBlock]$Script)
{
    $pref = "${ProgressPreference}"
    $ProgressPreference = "SilentlyContinue"

    & ${Script}

    $ProgressPreference = "${pref}"
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
