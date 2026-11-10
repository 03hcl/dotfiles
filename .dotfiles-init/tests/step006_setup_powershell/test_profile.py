"""Tests for Invoke-LinuxLikeSSHCopyId (ssh-copy-id) in profile.ps1.

Each test runs the function in pwsh and Windows PowerShell 5.1 (whichever exist) with a fake ssh.
The fake ssh runs the remote command with busybox sh in a temporary home directory.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
PROFILE = HERE.parents[1] / "step006_setup_powershell" / "profile.ps1"
FAKE_SSH = HERE / "fake_ssh.py"

SHELLS = [shell for shell in ("pwsh", "powershell") if shutil.which(shell)]
BUSYBOX = shutil.which("busybox")
requires_busybox = pytest.mark.skipif(not BUSYBOX, reason="busybox is required to emulate the remote shell")

VERSION = re.search(r'^\$__profileVersion = "(.*)"', PROFILE.read_text(encoding="utf-8"), re.MULTILINE)[1]
DESTINATION = "user@host.invalid"
PUBLIC_KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDummyKeyForTest user@example"
PRIVATE_KEY = "-----BEGIN OPENSSH PRIVATE KEY----- dummy"

# Load only definitions to avoid side effects of profile.ps1 (chcp, PSReadLine settings, banner)
LOADER = r"""
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
$ast = [System.Management.Automation.Language.Parser]::ParseFile($env:TEST_PROFILE, [ref]$null, [ref]$null)
$definitions = $ast.EndBlock.Statements | Where-Object {
    ($_ -is [System.Management.Automation.Language.FunctionDefinitionAst]) -or
    ($_ -is [System.Management.Automation.Language.AssignmentStatementAst])
}
. ([ScriptBlock]::Create(($definitions | ForEach-Object { $_.Extent.Text }) -join "`n"))
function ssh { & $env:TEST_PYTHON $env:TEST_FAKE_SSH @args }
"""


@dataclass
class Result:
    returncode: int
    stdout: str
    stderr: str
    ssh_calls: list[list[str]]

    @property
    def ssh_args(self) -> list[str]:
        """Arguments of the only ssh call, except the last one (the remote command)."""
        assert len(self.ssh_calls) == 1, self
        return self.ssh_calls[0][:-1]

    @property
    def remote_command(self) -> str:
        assert len(self.ssh_calls) == 1, self
        return self.ssh_calls[0][-1]


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.encode("utf-8"))


def read_authorized_keys(home: Path) -> str:
    return (home / ".ssh" / "authorized_keys").read_bytes().decode("utf-8")


@pytest.fixture
def work(tmp_path: Path) -> Path:
    """Current directory of PowerShell, containing 'id_test' and 'id_test.pub'."""
    path = tmp_path / "work"
    write(path / "id_test", PRIVATE_KEY + "\n")
    write(path / "id_test.pub", PUBLIC_KEY + "\n")
    return path


@pytest.fixture
def home(tmp_path: Path) -> Path:
    """Home directory of the fake remote host."""
    path = tmp_path / "home"
    path.mkdir()
    return path


@pytest.fixture(params=SHELLS)
def ssh_copy_id(request: pytest.FixtureRequest, tmp_path: Path, work: Path, home: Path):
    """Return a function that runs `Invoke-LinuxLikeSSHCopyId <arguments>`."""
    shell = request.param
    script = tmp_path / "run.ps1"
    log = tmp_path / "ssh.log"
    env = {
        **os.environ,
        "TEST_PROFILE": str(PROFILE),
        "TEST_PYTHON": sys.executable,
        "TEST_FAKE_SSH": str(FAKE_SSH),
        "TEST_SSH_LOG": str(log),
        "TEST_REMOTE_HOME": str(home),
        "TEST_BUSYBOX": BUSYBOX or "",
    }

    def run(arguments: str) -> Result:
        script.write_text(
            f"{LOADER}\nInvoke-LinuxLikeSSHCopyId {arguments}\nexit $LASTEXITCODE\n", encoding="utf-8-sig"
        )
        log.unlink(missing_ok=True)
        process = subprocess.run(
            [shell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(script)],
            cwd=work,
            env=env,
            capture_output=True,
            encoding="utf-8",
            errors="replace",
            # NOTE: Use a separate console so that [Console]::OutputEncoding does not affect the caller's console
            creationflags=subprocess.CREATE_NO_WINDOW,
            timeout=120,
        )
        calls = [json.loads(line) for line in log.read_text(encoding="utf-8").splitlines()] if log.exists() else []
        return Result(process.returncode, process.stdout, process.stderr, calls)

    return run


# Arguments passed to ssh


def test_passes_destination(ssh_copy_id):
    result = ssh_copy_id(f"-i id_test {DESTINATION}")

    assert result.returncode == 0, result
    assert result.ssh_args == [DESTINATION]


def test_passes_port_and_ssh_options_after_double_dash(ssh_copy_id):
    result = ssh_copy_id(f"-i id_test -p 2222 -- -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL {DESTINATION}")

    assert result.returncode == 0, result
    assert result.ssh_args == [
        "-p", "2222", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=NUL", DESTINATION
    ]


# Identity file


@requires_busybox
def test_sends_pub_file_instead_of_private_key(ssh_copy_id, home):
    result = ssh_copy_id(f"-i id_test {DESTINATION}")

    assert result.returncode == 0, result
    assert read_authorized_keys(home) == PUBLIC_KEY + "\n"


@requires_busybox
@pytest.mark.parametrize("path", ["id_test.pub", "id_test.PUB"])
def test_uses_path_ending_with_pub_as_is(ssh_copy_id, home, path):
    result = ssh_copy_id(f"-i {path} {DESTINATION}")

    assert result.returncode == 0, result
    assert read_authorized_keys(home) == PUBLIC_KEY + "\n"


def test_does_not_call_ssh_when_only_private_key_exists(ssh_copy_id, work):
    write(work / "id_private_only", PRIVATE_KEY + "\n")

    result = ssh_copy_id(f"-i id_private_only {DESTINATION}")

    assert result.returncode != 0
    assert result.ssh_calls == []


# Remote command


def test_runs_remote_command_with_sh(ssh_copy_id):
    """The login shell of the remote user may not be POSIX compatible (e.g. fish, csh)."""
    result = ssh_copy_id(f"-i id_test {DESTINATION}")

    assert result.remote_command.startswith("exec sh -c '")


@requires_busybox
def test_appends_key_with_special_characters_as_is(ssh_copy_id, work, home):
    key = "ssh-ed25519 AAAAdummy it's \"quoted\" $HOME `date` %s \\n \\\\ ; && | * ! ~ \u9375"
    write(work / "id_special.pub", key + "\n")

    result = ssh_copy_id(f"-i id_special.pub {DESTINATION}")

    assert result.returncode == 0, result
    assert read_authorized_keys(home) == key + "\n"


@requires_busybox
def test_appends_every_line_of_pub_file(ssh_copy_id, work, home):
    write(work / "id_multi.pub", "ssh-ed25519 AAAA1 one\r\nssh-ed25519 AAAA2 two\r\n")

    result = ssh_copy_id(f"-i id_multi.pub {DESTINATION}")

    assert result.returncode == 0, result
    assert read_authorized_keys(home) == "ssh-ed25519 AAAA1 one\nssh-ed25519 AAAA2 two\n"


@requires_busybox
def test_adds_missing_newline_to_existing_authorized_keys(ssh_copy_id, home):
    write(home / ".ssh" / "authorized_keys", "ssh-ed25519 AAAA0 existing")

    result = ssh_copy_id(f"-i id_test {DESTINATION}")

    assert result.returncode == 0, result
    assert read_authorized_keys(home) == "ssh-ed25519 AAAA0 existing\n" + PUBLIC_KEY + "\n"


@requires_busybox
def test_does_not_add_blank_line_to_existing_authorized_keys(ssh_copy_id, home):
    write(home / ".ssh" / "authorized_keys", "ssh-ed25519 AAAA0 existing\n")

    result = ssh_copy_id(f"-i id_test {DESTINATION}")

    assert result.returncode == 0, result
    assert read_authorized_keys(home) == "ssh-ed25519 AAAA0 existing\n" + PUBLIC_KEY + "\n"


@requires_busybox
def test_skips_keys_already_installed_even_with_different_comment(ssh_copy_id, work, home):
    write(home / ".ssh" / "authorized_keys", "ssh-ed25519 AAAA1 old-comment\n")
    write(work / "id_multi.pub", "ssh-ed25519 AAAA1 one\nssh-ed25519 AAAA2 two\n")

    result = ssh_copy_id(f"-i id_multi.pub {DESTINATION}")

    assert result.returncode == 0, result
    assert read_authorized_keys(home) == "ssh-ed25519 AAAA1 old-comment\nssh-ed25519 AAAA2 two\n"


@requires_busybox
def test_force_appends_keys_already_installed(ssh_copy_id, home):
    write(home / ".ssh" / "authorized_keys", PUBLIC_KEY + "\n")

    result = ssh_copy_id(f"-f -i id_test {DESTINATION}")

    assert result.returncode == 0, result
    assert read_authorized_keys(home) == PUBLIC_KEY + "\n" + PUBLIC_KEY + "\n"


# Other options


def test_dry_run_prints_ssh_command_without_calling_ssh(ssh_copy_id):
    result = ssh_copy_id(f"-n -i id_test -p 2222 {DESTINATION}")

    assert result.returncode == 0, result
    assert result.stdout.startswith(f'"ssh" "-p" "2222" "{DESTINATION}" "exec sh -c ')
    assert result.ssh_calls == []


@pytest.mark.parametrize("flag", ["-h", "--help", "/?"])
def test_prints_help(ssh_copy_id, flag):
    result = ssh_copy_id(flag)

    assert result.returncode == 0, result
    assert "Usage:" in result.stdout
    assert result.ssh_calls == []


@pytest.mark.parametrize("flag", ["-V", "--version"])
def test_prints_version(ssh_copy_id, flag):
    result = ssh_copy_id(flag)

    assert result.returncode == 0, result
    assert result.stdout.strip() == VERSION
    assert result.ssh_calls == []
