from __future__ import annotations

import base64
import os
import shutil
import subprocess
from pathlib import Path

import pytest

STEP = Path(__file__).resolve().parents[2] / "step008_install_vs_code" / "windows.ps1"
SHELLS = [shell for shell in ("pwsh", "powershell") if shutil.which(shell)]


def run_powershell(shell: str, script: str) -> subprocess.CompletedProcess[str]:
    script = f"""
        Import-Module -Name {ps_literal(STEP.parent.parent / "windows_utils.psm1")} -Force
        {script}
    """
    encoded = base64.b64encode(script.encode("utf-16-le")).decode("ascii")
    env = {
        key: value for key, value in os.environ.items() if key.upper() != "PSMODULEPATH"
    }
    return subprocess.run(
        [shell, "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded],
        env=env,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
        timeout=30,
    )


def ps_literal(path: Path) -> str:
    return "'" + str(path).replace("'", "''") + "'"


def load_function(name: str) -> str:
    return f"""
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile({ps_literal(STEP)}, [ref]$tokens, [ref]$errors)
        if ($errors.Count) {{ throw $errors[0] }}
        $function = $ast.Find({{
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq "{name}"
        }}, $false)
        Invoke-Expression $function.Extent.Text
    """


@pytest.mark.parametrize("shell", SHELLS)
def test_installs_jsonc_recommendations(shell: str, tmp_path: Path) -> None:
    config = tmp_path / "extensions.json"
    config.write_text(
        """
        // User extension recommendations.
        {
          /* Keep both entries when setting up a new machine. */
          "recommendations": [
            "publisher.first",
            "publisher.second", // Inline comments are allowed.
          ],
        }
        """,
        encoding="utf-8",
    )
    script = f"""
        {load_function("Install-VSCodeExtensions")}
        $global:calls = 0
        $global:installArgs = @()
        function global:code {{
            $global:calls++
            $global:installArgs = @($args)
            $global:LASTEXITCODE = 0
        }}
        Install-VSCodeExtensions -Path {ps_literal(config)}
        if ($global:calls -ne 1) {{ throw "Expected one CLI invocation" }}
        ConvertTo-Json -InputObject $global:installArgs -Compress
    """

    result = run_powershell(shell, script)

    assert result.returncode == 0, result
    assert result.stdout.strip().splitlines()[-1] == (
        '["--install-extension","publisher.first",'
        '"--install-extension","publisher.second","--force"]'
    )


@pytest.mark.parametrize("shell", SHELLS)
def test_invalid_json_stops_before_installation(shell: str, tmp_path: Path) -> None:
    config = tmp_path / "extensions.json"
    config.write_text('{"recommendations": [', encoding="utf-8")
    script = f"""
        $ErrorActionPreference = "Stop"
        {load_function("Install-VSCodeExtensions")}
        function global:code {{ throw "CLI must not run" }}
        Install-VSCodeExtensions -Path {ps_literal(config)}
    """

    result = run_powershell(shell, script)

    assert result.returncode != 0
    assert "ConvertFrom-Json" in result.stderr + result.stdout
    assert "CLI must not run" not in result.stderr + result.stdout


@pytest.mark.parametrize("shell", SHELLS)
@pytest.mark.parametrize("original_options", [None, "--trace-warnings"])
@pytest.mark.parametrize("fail", [False, True])
def test_scopes_warning_suppression(
    shell: str, tmp_path: Path, original_options: str | None, fail: bool
) -> None:
    config = tmp_path / "extensions.json"
    config.write_text('{"recommendations":["publisher.first"]}', encoding="utf-8")
    options = "$null" if original_options is None else f"'{original_options}'"
    script = f"""
        $ErrorActionPreference = "Stop"
        {load_function("Install-VSCodeExtensions")}
        $env:NODE_OPTIONS = {options}
        $before = $env:NODE_OPTIONS
        $global:observedOptions = $null
        $failed = $false
        function global:code {{
            $global:observedOptions = $env:NODE_OPTIONS
            $global:LASTEXITCODE = 0
            {"throw 'Test install failure'" if fail else ""}
        }}
        try {{ Install-VSCodeExtensions -Path {ps_literal(config)} }}
        catch {{
            if ($_.Exception.Message -ne "Test install failure") {{ throw }}
            $failed = $true
        }}
        if ($env:NODE_OPTIONS -cne $before) {{ throw "NODE_OPTIONS was not restored" }}
        if ($failed -ne ${str(fail).lower()}) {{ throw "Unexpected failure state" }}
        Write-Output $global:observedOptions
    """

    result = run_powershell(shell, script)

    assert result.returncode == 0, result
    expected = f"{original_options or ''} --disable-warning=DEP0169".strip()
    assert result.stdout.strip().splitlines()[-1] == expected


@pytest.mark.parametrize("shell", SHELLS)
@pytest.mark.parametrize("exit_code", [0, 7])
def test_native_cli_exit_code(shell: str, tmp_path: Path, exit_code: int) -> None:
    config = tmp_path / "extensions.json"
    config.write_text('{"recommendations":["publisher.first"]}', encoding="utf-8")
    script = f"""
        $ErrorActionPreference = "Stop"
        Set-StrictMode -Version 3.0
        {load_function("Install-VSCodeExtensions")}
        $env:NODE_OPTIONS = "--trace-warnings"
        function global:code {{ & $env:ComSpec /d /c "exit {exit_code}" }}
        try {{ Install-VSCodeExtensions -Path {ps_literal(config)} }}
        finally {{
            if ($env:NODE_OPTIONS -cne "--trace-warnings") {{
                throw "NODE_OPTIONS was not restored"
            }}
        }}
    """

    result = run_powershell(shell, script)

    if exit_code:
        assert result.returncode != 0
        assert f"exit code: {exit_code}" in result.stderr + result.stdout
    else:
        assert result.returncode == 0, result
    assert "NODE_OPTIONS was not restored" not in result.stderr + result.stdout


@pytest.mark.parametrize("shell", SHELLS)
def test_version_failure_stops_before_configuration(shell: str) -> None:
    script = f"""
        $ErrorActionPreference = "Stop"
        Set-StrictMode -Version 3.0
        {load_function("Step8")}
        function Write-Step {{}}
        function Update-WinGetPackage {{}}
        function Import-Path {{}}
        function global:code {{ & $env:ComSpec /d /c "exit 9" }}
        function Update-VSCodeConfig {{ throw "Configuration must not run" }}
        Step8
    """

    result = run_powershell(shell, script)

    assert result.returncode != 0
    assert "Command failed (exit code: 9): code --version" in result.stderr + result.stdout
    assert "Configuration must not run" not in result.stderr + result.stdout


@pytest.mark.parametrize("shell", SHELLS)
@pytest.mark.parametrize("what_if", [False, True])
def test_skips_cli_when_no_extensions_are_selected(
    shell: str, tmp_path: Path, what_if: bool
) -> None:
    config = tmp_path / "extensions.json"
    config.write_text(
        '{"recommendations":["publisher.first"]}' if what_if else '{"recommendations":[]}',
        encoding="utf-8",
    )
    script = f"""
        {load_function("Install-VSCodeExtensions")}
        function global:code {{ throw "CLI must not run" }}
        Install-VSCodeExtensions -Path {ps_literal(config)} {"-WhatIf" if what_if else ""}
    """

    result = run_powershell(shell, script)

    assert result.returncode == 0, result
