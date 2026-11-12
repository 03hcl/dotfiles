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
def test_vscode_config_copies_back_up_existing_files(shell: str, tmp_path: Path) -> None:
    home = tmp_path / "home"
    appdata = home / "AppData" / "Roaming"
    user_config = appdata / "Code" / "User"
    step = tmp_path / "step008"
    (step / "snippets").mkdir(parents=True)

    for name in ("argv.json", "keybindings.json", "settings.json"):
        (step / name).write_text(f'{{"source":"{name}"}}', encoding="utf-8")
        target = user_config / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(f'{{"existing":"{name}"}}', encoding="utf-8")

    (step / "snippets" / "sample.code-snippets").write_text(
        '{"sample":{"prefix":"sample","body":"new"}}', encoding="utf-8"
    )
    snippet_target = user_config / "snippets" / "sample.code-snippets"
    snippet_target.parent.mkdir(parents=True)
    snippet_target.write_text(
        '{"sample":{"prefix":"sample","body":"old"}}', encoding="utf-8"
    )

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

        Update-VSCodeConfig -Name "argv.json"
        Update-VSCodeConfig -Name "keybindings.json"
        Update-VSCodeConfig -Name "settings.json"
        Update-VSCodeSnippets
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
    assert (user_config / "argv.json").read_text() == '{"source":"argv.json"}'
    assert (user_config / "keybindings.json").read_text() == '{"source":"keybindings.json"}'
    assert (user_config / "settings.json").read_text() == '{"source":"settings.json"}'
    assert snippet_target.read_text() == '{"sample":{"prefix":"sample","body":"new"}}'

    [backup_dir] = (home / ".orig").iterdir()
    assert {
        path.relative_to(backup_dir).as_posix(): path.read_text()
        for path in backup_dir.rglob("*")
        if path.is_file()
    } == {
        "AppData/Roaming/Code/User/argv.json": '{"existing":"argv.json"}',
        "AppData/Roaming/Code/User/keybindings.json": '{"existing":"keybindings.json"}',
        "AppData/Roaming/Code/User/settings.json": '{"existing":"settings.json"}',
        "AppData/Roaming/Code/User/snippets/sample.code-snippets": (
            '{"sample":{"prefix":"sample","body":"old"}}'
        ),
    }
