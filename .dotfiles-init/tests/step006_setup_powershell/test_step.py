from __future__ import annotations

import base64
import json
import os
import subprocess

import pytest

from conftest import write
from test_windows import INIT_DIR, SHELLS

STEP = INIT_DIR / "step006_setup_powershell" / "windows.ps1"
FUNCTIONS = [
    "Update-PowerShell",
    "Update-PowerShellProfile",
    "Update-ExecutionPolicy",
    "Enable-DeveloperMode",
    "Install-BusyBox",
    "Install-Cygwin",
    "Install-CygwinPackages",
    "Install-Jq",
    "Step6",
]
EXPECTED_EVENTS = {
    "Update-PowerShell": ["winget", "path", "command", "command"],
    "Update-PowerShellProfile": ["command", "copy", "copy"],
    "Update-ExecutionPolicy": ["policy", "command"],
    "Enable-DeveloperMode": ["process"],
    "Install-BusyBox": ["winget", "link", "import-path", "command"],
    "Install-Cygwin": ["winget", *(["path"] * 6), "command"],
    "Install-CygwinPackages": ["download", "process", "command"],
    "Install-Jq": ["winget", "link", "import-path", "command"],
}


@pytest.mark.parametrize("shell", SHELLS)
@pytest.mark.parametrize("mode", ["execute", "what-if", "confirm"])
def test_step6_functions_respect_should_process(shell, mode, tmp_path):
    profile = tmp_path / "profile.ps1"
    write(profile, '$global:events.Add("profile")\n')
    options = {
        "execute": "-Confirm:$false",
        "what-if": "-WhatIf",
        "confirm": "-Confirm",
    }
    script = f"""
    $ErrorActionPreference = "Stop"
    Import-Module "{INIT_DIR / "windows_utils.psm1"}" -Force
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile("{STEP}", [ref]$tokens, [ref]$errors)
    if ($errors.Count) {{ throw $errors[0] }}
    foreach ($definition in $ast.FindAll({{
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }}, $false)) {{
        Invoke-Expression $definition.Extent.Text
    }}

    $global:events = [System.Collections.Generic.List[string]]::new()
    $PROFILE = [pscustomobject]@{{ CurrentUserAllHosts = "{profile}" }}
    $module = New-Module -ScriptBlock {{
        function Update-WinGetPackage {{
            [CmdletBinding(SupportsShouldProcess = $true)]
            param([string]$Id)
            $WhatIfPreference = $PSCmdlet.SessionState.PSVariable.GetValue("WhatIfPreference", $false)
            $ConfirmPreference = $PSCmdlet.SessionState.PSVariable.GetValue("ConfirmPreference", "High")
            if ($PSCmdlet.ShouldProcess($Id, "Install package")) {{ $global:events.Add("winget") }}
        }}
        function Update-Path {{
            [CmdletBinding(SupportsShouldProcess = $true)]
            param(
                [switch]$ForceFirst,
                [string]$Key,
                [Parameter(ValueFromRemainingArguments = $true)][string[]]$Values
            )
            $WhatIfPreference = $PSCmdlet.SessionState.PSVariable.GetValue("WhatIfPreference", $false)
            $ConfirmPreference = $PSCmdlet.SessionState.PSVariable.GetValue("ConfirmPreference", "High")
            if ($PSCmdlet.ShouldProcess(($Values -join ";"), "Update path")) {{ $global:events.Add("path") }}
        }}
        Export-ModuleMember Update-WinGetPackage, Update-Path
    }}
    Import-Module $module -Force
    function global:Write-CommandLog {{ param([scriptblock]$Script); $global:events.Add("command") }}
    function global:Copy-Resource {{ $global:events.Add("copy") }}
    function global:Import-Path {{ $global:events.Add("import-path") }}
    function global:New-WinGetPackageLink {{ $global:events.Add("link") }}
    function global:Set-ExecutionPolicy {{
        [CmdletBinding(SupportsShouldProcess = $true)]
        param([string]$ExecutionPolicy, [string]$Scope)
        if ($PSCmdlet.ShouldProcess($Scope, "Set policy")) {{ $global:events.Add("policy") }}
    }}
    function global:Start-Process {{ $global:events.Add("process") }}
    function global:Get-OnlineResource {{ $global:events.Add("download"); "setup.exe" }}
    function global:Get-TempDir {{ "{tmp_path}" }}
    function global:Test-Path {{ $false }}
    function global:powershell {{ "{profile}" }}
    function global:pwsh {{ "{profile}" }}

    {"$ConfirmPreference = 'Low'" if mode == "execute" else ""}
    $results = foreach ($name in @({", ".join(f'"{name}"' for name in FUNCTIONS)})) {{
        $global:events.Clear()
        $failure = $null
        try {{ & $name {options[mode]} }} catch {{ $failure = $_.Exception.Message }}
        [pscustomobject]@{{ Name = $name; Events = @($global:events); Error = $failure }}
    }}
    ConvertTo-Json -InputObject @($results) -Depth 4 -Compress
    """
    encoded = base64.b64encode(script.encode("utf-16-le")).decode("ascii")
    env = {key: value for key, value in os.environ.items() if key.upper() != "PSMODULEPATH"}
    result = subprocess.run(
        [shell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", encoded],
        capture_output=True,
        encoding="utf-8",
        errors="replace",
        env=env,
        timeout=30,
    )

    assert result.returncode == 0, result
    if mode == "what-if":
        assert "Install package" in result.stdout
        assert "Update path" in result.stdout
        assert "Create WinGet package command link" in result.stdout
        assert "Load PowerShell profile" in result.stdout
    data = json.loads(result.stdout.strip().splitlines()[-1])
    assert [item["Name"] for item in data] == FUNCTIONS
    for item in data:
        if mode == "execute":
            assert item["Error"] is None, item
            expected = EXPECTED_EVENTS.get(item["Name"])
            if expected is not None:
                assert item["Events"] == expected, item
            else:
                assert item["Events"] == [
                    *EXPECTED_EVENTS["Update-PowerShell"],
                    *EXPECTED_EVENTS["Update-PowerShellProfile"],
                    *EXPECTED_EVENTS["Update-ExecutionPolicy"],
                    "profile",
                    "path",
                    "command",
                    "command",
                    "command",
                    *EXPECTED_EVENTS["Install-BusyBox"],
                    *EXPECTED_EVENTS["Install-Jq"],
                    "command",
                    "command",
                ], item
        elif mode == "what-if":
            assert item["Error"] is None, item
            assert item["Events"] == [], item
        else:
            assert item["Error"] is not None, item
            assert item["Events"] == [], item
