from __future__ import annotations

import base64
import os
import shutil
import subprocess
from pathlib import Path

import pytest

INIT_DIR = Path(__file__).resolve().parents[2]
STEP_DIR = INIT_DIR / "step008_install_vs_code"
SHELLS = [shell for shell in ("pwsh", "powershell") if shutil.which(shell)]
ENTRY_POINT = '\nif ((-not ${MyInvocation}.ScriptName)'


def ps_literal(path: Path) -> str:
    return "'" + str(path).replace("'", "''") + "'"


@pytest.mark.parametrize("shell", SHELLS)
@pytest.mark.parametrize("populated_directories", [False, True])
@pytest.mark.parametrize("what_if", [False, True])
def test_vscode_config_copies_back_up_existing_files(
    shell: str, tmp_path: Path, populated_directories: bool, what_if: bool
) -> None:
    home = tmp_path / "home"
    appdata = home / "AppData" / "Roaming"
    user_config = appdata / "Code" / "User"
    step = tmp_path / "step008"
    expected = {}
    existing = {}
    for name in (
        "argv.json",
        "keybindings.json",
        "settings.json",
        "tasks.json",
        "mcp.json",
        "chatLanguageModels.json",
    ):
        content = (STEP_DIR / name).read_text(encoding="utf-8")
        (step / name).parent.mkdir(parents=True, exist_ok=True)
        (step / name).write_text(content, encoding="utf-8")
        target = home / ".vscode" / name if name == "argv.json" else user_config / name
        target.parent.mkdir(parents=True, exist_ok=True)
        existing[target] = f'{{"existing":"{name}"}}'
        target.write_text(existing[target], encoding="utf-8")
        expected[target] = content

    for directory, name in (
        ("snippets", "sample.code-snippets"),
        ("prompts", "nested/sample.prompt.md"),
    ):
        (step / directory).mkdir()
        (step / directory / ".gitignore").write_text("", encoding="utf-8")
        if populated_directories:
            source_file = step / directory / name
            source_file.parent.mkdir(parents=True, exist_ok=True)
            source_file.write_text("new", encoding="utf-8")
            target = user_config / directory / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("old", encoding="utf-8")
            existing[target] = "old"
            expected[target] = "new"

    unrelated = user_config / "prompts" / "local.prompt.md"
    unrelated.parent.mkdir(parents=True, exist_ok=True)
    unrelated.write_text("keep", encoding="utf-8")
    (step / "extensions.json").write_text('{"recommendations":[]}', encoding="utf-8")
    source = (STEP_DIR / "windows.ps1").read_text(encoding="utf-8")
    assert ENTRY_POINT in source
    (step / "windows.ps1").write_text(source.split(ENTRY_POINT, 1)[0], encoding="utf-8")

    script = f"""
        $ErrorActionPreference = "Stop"
        $env:USERPROFILE = {ps_literal(home)}
        $env:HOME = {ps_literal(home)}
        $env:APPDATA = {ps_literal(appdata)}
        function global:Read-Host {{ "y" }}
        Import-Module -Name {ps_literal(INIT_DIR / "windows_utils.psm1")} -Force
        . {ps_literal(step / "windows.ps1")}
        function Update-WinGetPackage {{}}
        function Import-Path {{}}
        function code {{ & $env:ComSpec /d /c "exit 0" }}

        Step8 {"-WhatIf" if what_if else ""}
        Step8 {"-WhatIf" if what_if else ""}
    """
    encoded = base64.b64encode(script.encode("utf-16-le")).decode("ascii")
    env = {key: value for key, value in os.environ.items() if key.upper() != "PSMODULEPATH"}
    result = subprocess.run(
        [shell, "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded],
        env=env,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
        timeout=30,
    )

    assert result.returncode == 0, result
    assert unrelated.read_text() == "keep"
    assert not (user_config / "argv.json").exists()
    for directory in ("snippets", "prompts"):
        assert not (user_config / directory / ".gitignore").exists()
        if not what_if:
            assert (user_config / directory).is_dir()
    for target, content in (existing if what_if else expected).items():
        assert target.read_text(encoding="utf-8") == content

    if what_if:
        assert not (home / ".orig").exists()
        return

    [backup_dir] = (home / ".orig").iterdir()
    assert {
        path.relative_to(backup_dir).as_posix(): path.read_text()
        for path in backup_dir.rglob("*")
        if path.is_file()
    } == {
        target.relative_to(home).as_posix(): content
        for target, content in existing.items()
    }
