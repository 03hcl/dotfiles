"""Tests for running windows.ps1 in the ways .dotfiles-init/README.md describes.

Each test runs in pwsh and Windows PowerShell 5.1 (whichever exist) with a fake winget.
USERPROFILE is a temporary directory, and git fetches from a local bare repository instead of GitHub.
"""

from __future__ import annotations

import base64
import os
import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

import pytest

from conftest import GITHUB_URL, Remote, git, read_tree, write

HERE = Path(__file__).resolve().parent
INIT_DIR = HERE.parent

SHELLS = [shell for shell in ("pwsh", "powershell") if shutil.which(shell)]

# A step loaded in the same way as the real steps, using functions of both windows.ps1 and windows_utils.psm1
TEST_STEP = r"""
Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"

function Step999 {
    Write-Step 999 "Test Step"
    Write-Log "Temp: $(Get-TempDir)"
}

if ((-not ${MyInvocation}.ScriptName) -or (${MyInvocation}.ScriptName -ne "${PSCommandPath}")) {
    Import-Module -Name "$(Join-Path ("${PSCommandPath}" | Split-Path | Split-Path) "windows_utils.psm1")" -Force
    Step999 -Args $args
}
"""

REMOTE_FILES = {
    ".dotfiles-init/windows.ps1": (INIT_DIR / "windows.ps1").read_text(encoding="utf-8"),
    ".dotfiles-init/windows_utils.psm1": (INIT_DIR / "windows_utils.psm1").read_text(encoding="utf-8"),
    ".dotfiles-init/step998_test/linux.sh": "#!/usr/bin/env sh\n",
    ".dotfiles-init/step999_test/windows.ps1": TEST_STEP,
}

PROLOGUE = r"""
$ErrorActionPreference = "Stop"
# Guard against installing into the real home directory
if (($HOME -ne $env:TEST_HOME) -or ($env:USERPROFILE -ne $env:TEST_HOME)) { throw "HOME is not redirected: ${HOME}" }
function global:winget { Add-Content -LiteralPath $env:TEST_WINGET_LOG -Value ($args -join " "); "v0.0.0-fake" }
# NOTE: `git remote get-url` expands url.<base>.insteadOf (see conftest.py), so map it back to GitHub
function global:git { & git.exe @args | ForEach-Object { "$_".Replace($env:TEST_REMOTE, $env:TEST_GITHUB_URL) } }
function global:Read-Host { Write-Host "$args"; $env:TEST_ANSWER }
"""

BACKUP_NAME = re.compile(r"\d{8}_\d{6}_\d+")

WINGET_CALLS = ["--version", "install --silent --exact --source winget --id Git.Git"]


@dataclass
class Result:
    returncode: int
    stdout: str
    stderr: str
    winget_calls: list[str]


@pytest.fixture
def home(tmp_path: Path) -> Path:
    path = tmp_path / "home"
    path.mkdir()
    return path


@pytest.fixture(params=SHELLS)
def run(request: pytest.FixtureRequest, tmp_path: Path, remote: Remote, home: Path):
    """Return a function that runs a command as if it is typed in a new PowerShell console."""
    shell = request.param
    log = tmp_path / "winget.log"
    # NOTE: Drop PSModulePath inherited from pwsh, or Windows PowerShell 5.1 loads modules of pwsh and fails
    env = {
        **{key: value for key, value in remote.env.items() if key.upper() != "PSMODULEPATH"},
        "HOME": str(home),
        "USERPROFILE": str(home),
        "TEST_HOME": str(home),
        "TEST_WINGET_LOG": str(log),
        "TEST_REMOTE": remote.path.as_posix(),
        "TEST_GITHUB_URL": GITHUB_URL,
        "TEST_WINDOWS_PS1": str(INIT_DIR / "windows.ps1"),
    }

    def run(command: str, execution_policy: str = "RemoteSigned", answer: str = "") -> Result:
        log.unlink(missing_ok=True)
        # NOTE: Use -EncodedCommand instead of -File, because `${MyInvocation}.ScriptName` is empty only from the console
        encoded = base64.b64encode(f"{PROLOGUE}\n{command}\n".encode("utf-16-le")).decode("ascii")
        process = subprocess.run(
            [shell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", execution_policy, "-EncodedCommand", encoded],
            cwd=tmp_path,
            env={**env, "TEST_ANSWER": answer},
            stdin=subprocess.DEVNULL,
            capture_output=True,
            encoding="utf-8",
            errors="replace",
            # NOTE: Use a separate console so that [Console]::OutputEncoding does not affect the caller's console
            creationflags=subprocess.CREATE_NO_WINDOW,
            timeout=300,
        )
        calls = log.read_text(encoding="utf-8").splitlines() if log.exists() else []
        return Result(process.returncode, process.stdout, process.stderr, calls)

    return run


def assert_completed(result: Result, steps: int = 2) -> None:
    assert result.returncode == 0, result
    assert result.stdout.count("Hello, Windows!") == 1, result
    assert "Successfully completed!" in result.stdout, result
    assert f"Found {steps} additional steps." in result.stdout, result
    assert result.stdout.count("Step 999: Test Step") == 1, result
    assert result.winget_calls == WINGET_CALLS


def assert_cloned(repo: Path, remote: Remote) -> None:
    assert read_tree(repo) == read_tree(remote.work)
    assert git("-C", str(repo), "config", "remote.origin.url", env=remote.env) == GITHUB_URL
    assert git("-C", str(repo), "status", "--porcelain", env=remote.env) == ""
    assert git("-C", str(repo), "rev-parse", "--abbrev-ref", "HEAD", "@{upstream}", env=remote.env) == "main\norigin/main"


@pytest.mark.parametrize(
    "command, execution_policy",
    [
        # README.md: iwr "https://raw.githubusercontent.com/.../windows.ps1" | iex
        # NOTE: Restricted is the default of Windows PowerShell 5.1 on Windows clients
        ('Get-Content -Raw -Encoding UTF8 -LiteralPath "$env:TEST_WINDOWS_PS1" | Invoke-Expression', "Restricted"),
        ('& "$env:TEST_WINDOWS_PS1"', "RemoteSigned"),
        ('. "$env:TEST_WINDOWS_PS1"', "RemoteSigned"),
    ],
    ids=["iex", "call", "dot-source"],
)
def test_installs_repository(run, remote, home, command, execution_policy):
    remote.push(REMOTE_FILES)

    result = run(command, execution_policy)

    assert_completed(result)
    assert_cloned(home / ".dotfiles", remote)


def test_updates_repository(run, remote, home):
    remote.push(REMOTE_FILES)
    git("clone", "--quiet", GITHUB_URL, str(home / ".dotfiles"), env=remote.env)
    remote.push({"README.md": "updated\n"})

    # README.md: Update
    result = run(r'& "$HOME\.dotfiles\.dotfiles-init\windows.ps1"')

    assert_completed(result)
    assert_cloned(home / ".dotfiles", remote)


def test_runs_single_step(run, remote, home):
    """With only one step directory, Get-ChildItem returns a single item instead of an array."""
    remote.push({name: text for name, text in REMOTE_FILES.items() if "step998" not in name})

    result = run('& "$env:TEST_WINDOWS_PS1"')

    assert_completed(result, steps=1)


def test_backs_up_unexpected_directory(run, remote, home):
    remote.push(REMOTE_FILES)
    write(home / ".dotfiles" / "old.txt", "old\n")

    result = run('& "$env:TEST_WINDOWS_PS1"', answer="y")

    assert_completed(result)
    assert_cloned(home / ".dotfiles", remote)
    [backup] = (home / ".orig").iterdir()
    assert BACKUP_NAME.fullmatch(backup.name), backup
    assert read_tree(backup) == {".dotfiles/old.txt": "old\n"}


def test_aborts_backup_when_declined(run, remote, home):
    remote.push(REMOTE_FILES)
    write(home / ".dotfiles" / "old.txt", "old\n")

    result = run('& "$env:TEST_WINDOWS_PS1"', answer="n")

    assert result.returncode != 0, result
    assert "Aborted by user." in result.stdout + result.stderr, result
    assert read_tree(home / ".dotfiles", skip=()) == {"old.txt": "old\n"}
    assert not (home / ".orig").exists()


@pytest.mark.parametrize("operator", ["&", "."])
def test_runs_step_alone(run, tmp_path, operator):
    """A step imports windows.ps1 through windows_utils.psm1, which must not start the installer."""
    for name, text in REMOTE_FILES.items():
        write(tmp_path / "repo" / name, text)

    result = run(f'{operator} "{tmp_path / "repo" / ".dotfiles-init" / "step999_test" / "windows.ps1"}"')

    assert result.returncode == 0, result
    assert result.stdout.count("Step 999: Test Step") == 1, result
    assert f"Temp: {os.environ['TEMP']}\\.dotfiles-init" in result.stdout, result
    assert "Hello, Windows!" not in result.stdout, result
    assert result.winget_calls == []
