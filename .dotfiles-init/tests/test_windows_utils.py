"""Tests for functions in windows_utils.psm1.

Each test runs in pwsh and Windows PowerShell 5.1 (whichever exist).
Update-Path writes to a temporary registry key instead of HKCU\\Environment.
"""

from __future__ import annotations

import base64
import codecs
import os
import re
import subprocess
import uuid
import winreg
from pathlib import Path

import pytest

from conftest import read_tree, write
from test_windows import INIT_DIR, SHELLS

PROLOGUE = f"""
$ErrorActionPreference = "Stop"
Import-Module -Name "{INIT_DIR / "windows_utils.psm1"}" -Force
function global:Read-Host {{ Write-Host "$args"; $env:TEST_ANSWER }}
"""

KEY = "TestPath"


@pytest.mark.parametrize("scenario", ["move", "declined", "existing-target"])
def test_backup_file_moves_only_after_confirmation_to_unused_target(run, home, scenario):
    source = home / "source.txt"
    target = home / "backup" / "source.txt"
    write(source, "original\n")
    if scenario == "existing-target":
        write(target, "previous backup\n")

    result = run(
        f'Backup-File -Source "{source}" -Target "{target}"',
        answer="n" if scenario == "declined" else "y",
        check=False,
    )

    if scenario == "move":
        assert result.returncode == 0, result
        assert not source.exists()
        assert target.read_text() == "original\n"
    else:
        assert result.returncode != 0, result
        assert source.read_text() == "original\n"
        if scenario == "existing-target":
            assert "Backup target already exists." in result.stderr
            assert target.read_text() == "previous backup\n"
        else:
            assert "Aborted by user." in result.stderr
            assert not target.parent.exists()


@pytest.fixture
def home(tmp_path: Path) -> Path:
    path = tmp_path / "home"
    path.mkdir()
    return path


@pytest.fixture(params=SHELLS)
def run(request: pytest.FixtureRequest, tmp_path: Path, home: Path):
    shell = request.param
    # NOTE: Drop PSModulePath inherited from pwsh, or Windows PowerShell 5.1 loads modules of pwsh and fails
    env = {key: value for key, value in os.environ.items() if key.upper() != "PSMODULEPATH"}
    env.update({"HOME": str(home), "USERPROFILE": str(home), "TEST_LOG": str(tmp_path / "test.log")})

    def run(command: str, answer: str = "y", check: bool = True) -> subprocess.CompletedProcess[str]:
        encoded = base64.b64encode(f"{PROLOGUE}\n{command}\n".encode("utf-16-le")).decode("ascii")
        process = subprocess.run(
            [shell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", encoded],
            cwd=tmp_path,
            env={**env, "TEST_ANSWER": answer},
            stdin=subprocess.DEVNULL,
            capture_output=True,
            encoding="utf-8",
            errors="replace",
            creationflags=subprocess.CREATE_NO_WINDOW,
            timeout=120,
        )
        if check:
            assert process.returncode == 0, process
        return process

    return run


@pytest.mark.parametrize("direct", [False, True])
@pytest.mark.parametrize("exit_code", [0, 7])
def test_command_log_checks_native_exit_code(run, direct, exit_code):
    result = run(
        f"""
        Write-CommandLog {{
            & $env:ComSpec /d /c "echo native-output & exit {exit_code}" | ForEach-Object {{ $_ }}
        }} -IsDirectOutput ${str(direct).lower()}
        Write-Output "completed"
        """,
        check=False,
    )

    assert "native-output" in result.stdout
    if exit_code:
        assert result.returncode != 0
        assert f"Command failed (exit code: {exit_code})" in result.stderr
        assert "completed" not in result.stdout
    else:
        assert result.returncode == 0, result
        assert "completed" in result.stdout


@pytest.mark.parametrize("direct", [False, True])
@pytest.mark.parametrize(
    "exit_code, success_exit_codes, succeeds",
    [(0, "0", True), (7, "0, 7", True), (7, "0", False)],
)
def test_command_log_accepts_only_configured_exit_codes(run, direct, exit_code, success_exit_codes, succeeds):
    result = run(
        f"""
        Write-CommandLog {{
            & $env:ComSpec /d /c "echo native-output & exit {exit_code}"
        }} -IsDirectOutput ${str(direct).lower()} -SuccessExitCodes @({success_exit_codes})
        Write-Output "exit-code=$global:LASTEXITCODE"
        Write-Output "completed"
        """,
        check=False,
    )

    assert "native-output" in result.stdout
    if succeeds:
        assert result.returncode == 0, result
        assert f"exit-code={exit_code}" in result.stdout
        assert "completed" in result.stdout
    else:
        assert result.returncode != 0
        assert "Command failed (exit code: 7)" in result.stderr
        assert "completed" not in result.stdout


@pytest.mark.parametrize("direct", [False, True])
def test_installer_disables_native_error_preference(run, tmp_path, direct):
    script = tmp_path / "command.ps1"
    write(
        script,
        f"""
        $PSNativeCommandUseErrorActionPreference = $true
        . "{INIT_DIR / "windows.ps1"}"
        Write-CommandLog {{
            & $env:ComSpec /d /c "exit 7"
        }} -IsDirectOutput ${str(direct).lower()} -SuccessExitCodes @(0, 7)
        Write-Output "exit-code=$global:LASTEXITCODE"
        """,
    )

    result = run(f'& "{script}"')

    assert "exit-code=7" in result.stdout, result
    assert "Hello, Windows!" not in result.stdout


@pytest.mark.parametrize("direct", [False, True])
def test_command_log_ignores_stale_exit_code_and_preserves_output(run, direct):
    result = run(
        f"""
        & $env:ComSpec /d /c "exit 7"
        $output = @(Write-CommandLog {{ 42 }} -IsDirectOutput ${str(direct).lower()})
        if ($output.Count -ne {1 if direct else 0}) {{ throw "Unexpected output count" }}
        {"if ($output[0] -ne 42) { throw 'Output changed' }" if direct else ""}
        Write-CommandLog {{ Get-Item -LiteralPath $env:USERPROFILE }}
        """
    )

    assert result.returncode == 0, result
    assert "Command failed" not in result.stdout + result.stderr


@pytest.mark.parametrize("direct", [False, True])
def test_command_log_preserves_powershell_errors(run, direct):
    result = run(
        f'Write-CommandLog {{ throw "original-error" }} -IsDirectOutput ${str(direct).lower()}',
        check=False,
    )

    assert result.returncode != 0
    assert "original-error" in result.stderr


@pytest.mark.parametrize("exit_code", [0, -1978335189, 7])
def test_winget_install_accepts_only_success_and_no_update(run, exit_code):
    result = run(
        f"""
        function global:winget {{ & $env:ComSpec /d /c "exit {exit_code}" }}
        Update-WinGetPackage "Test.Package"
        Write-Output "completed"
        """,
        check=False,
    )

    if exit_code in (0, -1978335189):
        assert result.returncode == 0, result
        assert "completed" in result.stdout
    else:
        assert result.returncode != 0
        assert "Command failed (exit code: 7)" in result.stderr
        assert "completed" not in result.stdout


def test_import_caller_preference_only_changes_calling_function_scope(run):
    result = run(
        """
        $WhatIfPreference = $false
        $ConfirmPreference = "High"
        $module = New-Module {
            $WhatIfPreference = $false
            $ConfirmPreference = "High"
            function Invoke-Inner {
                [CmdletBinding(SupportsShouldProcess = $true)]
                param()
                Import-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
                Write-Output "inner=$WhatIfPreference,$ConfirmPreference"
            }
            function Get-ModulePreference {
                Write-Output "module=$WhatIfPreference,$ConfirmPreference"
            }
        }
        Import-Module $module
        function Invoke-Outer {
            [CmdletBinding(SupportsShouldProcess = $true)]
            param()
            Invoke-Inner
        }
        Invoke-Outer -WhatIf -Confirm:$false
        Get-ModulePreference
        Write-Output "outer=$WhatIfPreference,$ConfirmPreference"
        """
    )
    assert "inner=True,None" in result.stdout
    assert "module=False,High" in result.stdout
    assert "outer=False,High" in result.stdout


def test_import_caller_preference_inherits_all_common_preference_variables(run):
    result = run(
        """
        $module = New-Module {
            $WhatIfPreference = $false
            $ConfirmPreference = "High"
            $DebugPreference = "SilentlyContinue"
            $ErrorActionPreference = "Continue"
            $InformationPreference = "SilentlyContinue"
            $ProgressPreference = "Continue"
            $VerbosePreference = "SilentlyContinue"
            $WarningPreference = "Continue"
            function Invoke-Inner {
                [CmdletBinding()]
                param()
                Import-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
                Write-Output "inner=$WhatIfPreference,$ConfirmPreference,$DebugPreference,$ErrorActionPreference,$InformationPreference,$ProgressPreference,$VerbosePreference,$WarningPreference"
            }
            function Get-ModulePreference {
                Write-Output "module=$WhatIfPreference,$ConfirmPreference,$DebugPreference,$ErrorActionPreference,$InformationPreference,$ProgressPreference,$VerbosePreference,$WarningPreference"
            }
        }
        Import-Module $module
        function Invoke-Outer {
            [CmdletBinding()]
            param()
            $WhatIfPreference = $true
            $ConfirmPreference = "None"
            $DebugPreference = "Continue"
            $ErrorActionPreference = "Stop"
            $InformationPreference = "Continue"
            $ProgressPreference = "SilentlyContinue"
            $VerbosePreference = "Continue"
            $WarningPreference = "SilentlyContinue"
            Invoke-Inner
        }
        Invoke-Outer
        Get-ModulePreference
        """
    )
    assert "inner=True,None,Continue,Stop,Continue,SilentlyContinue,Continue,SilentlyContinue" in result.stdout
    assert "module=False,High,SilentlyContinue,Continue,SilentlyContinue,Continue,SilentlyContinue,Continue" in result.stdout


@pytest.mark.parametrize("command", ["path", "winget"])
@pytest.mark.parametrize(
    "outer_args, inner_args, executed, succeeds",
    [
        ("-WhatIf", "", False, True),
        ("-WhatIf", "-WhatIf:$false", True, True),
        ("-Confirm", "", False, False),
        ("-Confirm", "-Confirm:$false", True, True),
        ("-Confirm:$false", "", True, True),
    ],
)
def test_module_commands_inherit_caller_preferences(run, registry, command, outer_args, inner_args, executed, succeeds):
    registry.set(r"C:\original")
    result = run(
        f"""
        function global:winget {{ Write-Output "winget-executed" }}
        $ConfirmPreference = "{'Low' if outer_args == '-Confirm:$false' else 'High'}"
        function Invoke-Setup {{
            [CmdletBinding(SupportsShouldProcess = $true)]
            param()
            {
                f'Update-Path -Path "{registry.ps_path}" -Key "{KEY}" "C:\\new" {inner_args}'
                if command == "path"
                else f'Update-WinGetPackage "Test.Package" {inner_args}'
            }
        }}
        Invoke-Setup {outer_args}
        """,
        check=False,
    )

    assert (result.returncode == 0) == succeeds, result
    assert ("winget-executed" in result.stdout) == (executed and command == "winget"), result
    expected = r"C:\new;C:\original" if executed and command == "path" else r"C:\original"
    assert registry.get() == (expected, winreg.REG_EXPAND_SZ)


class Registry:
    """Temporary registry key under HKCU that stands in for HKCU\\Environment."""

    def __init__(self) -> None:
        self.sub = rf"Software\dotfiles-init-test-{uuid.uuid4()}"
        self.ps_path = rf"HKCU:\{self.sub}"
        winreg.CreateKey(winreg.HKEY_CURRENT_USER, self.sub).Close()

    def set(self, value: str, kind: int = winreg.REG_EXPAND_SZ, name: str = KEY) -> None:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, self.sub, 0, winreg.KEY_SET_VALUE) as key:
            winreg.SetValueEx(key, name, 0, kind, value)

    def get(self, name: str = KEY) -> tuple[str, int] | None:
        """(raw value, kind). %...% is not expanded."""
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, self.sub) as key:
            try:
                return winreg.QueryValueEx(key, name)
            except FileNotFoundError:
                return None

    def delete(self) -> None:
        winreg.DeleteKey(winreg.HKEY_CURRENT_USER, self.sub)


@pytest.fixture
def registry():
    registry = Registry()
    yield registry
    registry.delete()


def update_path(registry: Registry, args: str, key: str = KEY) -> str:
    return f'Update-Path -Path "{registry.ps_path}" -Key "{key}" {args}'


def test_prepends_values_in_given_order(run, registry):
    registry.set(r"C:\a;%SystemRoot%\b")

    run(update_path(registry, r'"C:\x" "%USERPROFILE%\y"'))

    assert registry.get() == (r"C:\x;%USERPROFILE%\y;C:\a;%SystemRoot%\b", winreg.REG_EXPAND_SZ)


def test_writes_expand_sz_over_sz(run, registry):
    """%...% in Path must be expanded by Windows, so the value must be REG_EXPAND_SZ."""
    registry.set(r"%SystemRoot%\b", winreg.REG_SZ)

    run(update_path(registry, r'"%USERPROFILE%\y"'))

    assert registry.get() == (r"%USERPROFILE%\y;%SystemRoot%\b", winreg.REG_EXPAND_SZ)


def test_creates_missing_value(run, registry):
    run(update_path(registry, r'"C:\x"'))

    assert registry.get() == (r"C:\x", winreg.REG_EXPAND_SZ)


def test_skips_existing_value_compared_after_expansion(run, registry):
    registry.set(r"C:\a;%USERPROFILE%\y", winreg.REG_SZ)

    run(update_path(registry, r'"$env:USERPROFILE\y"'))

    assert registry.get() == (r"C:\a;%USERPROFILE%\y", winreg.REG_SZ)


def test_force_first_moves_existing_value(run, registry):
    registry.set(r"C:\a;C:\b;C:\c")

    run(update_path(registry, r'-ForceFirst "C:\c" "C:\b"'))

    assert registry.get() == (r"C:\c;C:\b;C:\a", winreg.REG_EXPAND_SZ)


def test_trims_and_drops_blank_entries(run, registry):
    registry.set(r" C:\a ;; ;C:\b;")

    run(update_path(registry, r'"  C:\x  " " "'))

    assert registry.get() == (r"C:\x;C:\a;C:\b", winreg.REG_EXPAND_SZ)


def test_what_if_does_not_write(run, registry):
    registry.set(r"C:\a", winreg.REG_SZ)

    result = run(update_path(registry, r'-WhatIf "C:\x"'))

    assert registry.get() == (r"C:\a", winreg.REG_SZ)
    assert r"Set Key: 'TestPath' to Value: 'C:\x;C:\a'" in result.stdout, result


def test_key_path_reloads_env_path(run, registry):
    """Updating Path reloads $env:Path of the current process (Import-Path)."""
    registry.set(r"C:\a", name="Path")

    command = update_path(registry, r'"C:\x"', key="Path")
    result = run(f'$env:Path = "marker"; {command}; "env:Path=$env:Path"')

    assert registry.get("Path") == (r"C:\x;C:\a", winreg.REG_EXPAND_SZ)
    assert "env:Path=" in result.stdout, result
    assert "env:Path=marker" not in result.stdout, result


def test_scripts_are_readable_by_windows_powershell():
    """Windows PowerShell 5.1 reads a BOM-less file in the ANSI code page (e.g. cp932), which breaks non-ASCII lines."""
    for name in ("windows.ps1", "windows_utils.psm1"):
        data = (INIT_DIR / name).read_bytes()
        assert data.startswith(codecs.BOM_UTF8) or data.isascii(), name


# Backup directory: ~\.orig\<yyyyMMdd_HHmmss>_<PID>\<path relative to ~, or the full path without ':'>
BACKUP_NAME = re.compile(r"\d{8}_\d{6}_\d+")


def backups(home: Path) -> list[Path]:
    """Backup directories under ~\\.orig."""
    root = home / ".orig"
    if not root.exists():
        return []
    paths = sorted(root.iterdir())
    assert all(BACKUP_NAME.fullmatch(path.name) for path in paths), paths
    return paths


def outside_home_path(path: Path) -> str:
    return str(path).replace(":", "", 1)


@pytest.fixture
def step(tmp_path: Path) -> Path:
    """Directory of a step that calls the functions. Relative Source paths are relative to it."""
    path = tmp_path / "repo" / ".dotfiles-init" / "step999_test"
    write(path / "a.txt", "new\n")
    return path


def call_from_step(run, step: Path, command: str, **kwargs):
    write(step / "windows.ps1", f"{command}\n")
    return run(f'& "{step / "windows.ps1"}"', **kwargs)


def copy_resource(run, step: Path, target: Path, **kwargs):
    return call_from_step(run, step, f'Copy-Resource -Source "a.txt" -Target "{target}" > $null', **kwargs)


def assert_step_untouched(step: Path) -> None:
    assert sorted(read_tree(step)) == ["a.txt", "windows.ps1"]


def test_copy_resource_copies_to_missing_target(run, home, step):
    target = home / "x" / "a.txt"

    result = copy_resource(run, step, target)

    assert target.read_text() == "new\n"
    assert " -> Copied." in result.stdout, result
    assert backups(home) == []


def test_copy_resource_skips_same_content(run, home, step):
    target = home / "x" / "a.txt"
    write(target, "new\n")

    result = copy_resource(run, step, target)

    assert target.read_text() == "new\n"
    assert " -> Already exists." in result.stdout, result
    assert backups(home) == []


def test_copy_resource_backs_up_different_content(run, home, step):
    target = home / "x" / "a.txt"
    write(target, "old\n")

    copy_resource(run, step, target)

    assert target.read_text() == "new\n"
    [backup] = backups(home)
    assert read_tree(backup) == {"x/a.txt": "old\n"}
    assert_step_untouched(step)


def test_copy_resource_aborts_when_backup_declined(run, home, step):
    target = home / "x" / "a.txt"
    write(target, "old\n")

    result = copy_resource(run, step, target, answer="n", check=False)

    assert result.returncode != 0, result
    assert "Confirm backup? [y/N]" in result.stdout, result
    assert target.read_text() == "old\n"
    assert backups(home) == []


def test_copy_resource_treats_brackets_literally(run, home, step):
    """`-Path` treats [...] as a wildcard, so `Test-Path` would miss the existing file."""
    target = home / "x[1]" / "a.txt"
    write(target, "old\n")

    copy_resource(run, step, target)

    assert target.read_text() == "new\n"
    [backup] = backups(home)
    assert read_tree(backup) == {"x[1]/a.txt": "old\n"}


def test_backups_of_a_process_share_one_directory(run, home, step):
    """Each step imports windows_utils.psm1 again with -Force, but the time of the first backup is kept."""
    for name in ("a", "b"):
        write(home / name / "a.txt", "old\n")
    module = INIT_DIR / "windows_utils.psm1"
    command = "\n".join(
        f'Import-Module -Name "{module}" -Force; Copy-Resource -Source "a.txt" -Target "{home / name / "a.txt"}" > $null; Start-Sleep 1'
        for name in ("a", "b")
    )

    call_from_step(run, step, command)

    [backup] = backups(home)
    assert read_tree(backup) == {"a/a.txt": "old\n", "b/a.txt": "old\n"}


def test_copy_resource_backs_up_target_outside_home(run, tmp_path, home, step):
    target = tmp_path / "outside" / "a.txt"
    write(target, "old\n")

    copy_resource(run, step, target)

    assert target.read_text() == "new\n"
    [backup] = backups(home)
    assert (backup / outside_home_path(target)).read_text() == "old\n"
    assert_step_untouched(step)


# NOTE: Creating a symbolic link needs elevation (or developer mode), so a fake Start-Process records the command
FAKE_START_PROCESS = r"""
function global:Start-Process ($FilePath, $Verb, [switch]$Wait, $ArgumentList) {
    Set-Content -LiteralPath $env:TEST_LOG -Value "${FilePath} ${Verb} $(${ArgumentList}[-1])"
}
"""


def new_symlink(run, tmp_path: Path, step: Path, args: str) -> str:
    call_from_step(run, step, f"{FAKE_START_PROCESS}\nNew-SymLink {args} > $null")
    return (tmp_path / "test.log").read_text(encoding="utf-8-sig").strip()


def symlink_command(target: Path, source: Path) -> str:
    return f"pwsh.exe RunAs New-Item -Path '{target}' -Value '{source}' -ItemType 'SymbolicLink'"


def test_new_symlink_resolves_relative_source_from_caller(run, tmp_path, home, step):
    command = new_symlink(run, tmp_path, step, f'-Source "a.txt" -TargetDir "{home / "bin"}"')

    assert command == symlink_command(home / "bin" / "a.txt", step / "a.txt")
    assert (home / "bin").is_dir()


def test_new_symlink_keeps_absolute_source(run, tmp_path, home, step):
    """e.g. `New-SymLink -Source (Get-Command python).Source -TargetName "python3.exe"`"""
    source = tmp_path / "tool" / "tool.exe"

    command = new_symlink(run, tmp_path, step, f'-Source "{source}" -TargetName "tool3.exe"')

    assert command == symlink_command(home / ".local" / "bin" / "tool3.exe", source)


def test_new_symlink_backs_up_existing_file(run, tmp_path, home, step):
    target = home / ".local" / "bin" / "a.txt"
    write(target, "old\n")

    command = new_symlink(run, tmp_path, step, '-Source "a.txt"')

    assert command == symlink_command(target, step / "a.txt")
    assert not target.exists()
    [backup] = backups(home)
    assert read_tree(backup) == {".local/bin/a.txt": "old\n"}
    assert_step_untouched(step)
