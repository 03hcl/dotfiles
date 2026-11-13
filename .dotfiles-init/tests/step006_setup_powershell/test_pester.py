from __future__ import annotations

import base64
import json
import os
import subprocess
from pathlib import Path

import pytest

from test_windows import INIT_DIR, SHELLS

STEP = INIT_DIR / "step006_setup_powershell" / "windows.ps1"


@pytest.mark.parametrize("shell", SHELLS)
@pytest.mark.parametrize("what_if, exit_code", [(False, 0), (True, 0), (False, 7)])
def test_installs_pester_in_both_shells(shell, what_if, exit_code):
    script = f"""
    $ErrorActionPreference = "Stop"
    Import-Module "{INIT_DIR / "windows.ps1"}" -Force
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile("{STEP}", [ref]$tokens, [ref]$errors)
    if ($errors.Count) {{ throw $errors[0] }}
    $function = $ast.Find({{
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq "Install-Pester"
    }}, $false)
    if (-not $function) {{ throw "Install-Pester not found" }}
    Invoke-Expression $function.Extent.Text

    $global:calls = [System.Collections.Generic.List[object]]::new()
    function global:powershell {{
        $global:calls.Add([pscustomobject]@{{ Shell = "powershell"; Arguments = @($args) }})
        $global:LASTEXITCODE = {exit_code}
    }}
    function global:pwsh {{
        $global:calls.Add([pscustomobject]@{{ Shell = "pwsh"; Arguments = @($args) }})
        $global:LASTEXITCODE = {exit_code}
    }}
    Install-Pester -WhatIf:${str(what_if).lower()} -Confirm:$false
    ConvertTo-Json -InputObject @($global:calls) -Depth 4 -Compress
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

    if exit_code:
        assert result.returncode != 0, result
        assert "Command failed (exit code: 7)" in result.stderr
        return

    assert result.returncode == 0, result
    calls = json.loads(result.stdout.strip().splitlines()[-1])
    if what_if:
        assert calls == []
    else:
        assert [call["Shell"] for call in calls] == ["powershell", "pwsh"]
        for call in calls:
            assert call["Arguments"] == [
                "-NoProfile",
                "-Command",
                '$ErrorActionPreference = "Stop"; Install-Module -Name Pester -MinimumVersion 5.0 '
                '-Scope CurrentUser -Force -SkipPublisherCheck',
            ]
