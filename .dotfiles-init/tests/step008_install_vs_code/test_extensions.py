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
        }}
        Install-VSCodeExtensions -Path {ps_literal(config)}
        if ($global:calls -ne 1) {{ throw "Expected one CLI invocation" }}
        ConvertTo-Json -InputObject $global:installArgs -Compress
    """

    result = run_powershell(shell, script)

    assert result.returncode == 0, result
    assert result.stdout.strip() == (
        '["--force","--install-extension","publisher.first",'
        '"--install-extension","publisher.second"]'
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
    assert result.stdout.strip() == expected


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
