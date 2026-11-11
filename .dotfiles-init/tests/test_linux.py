"""Tests for installing the repository onto an existing home directory on Linux.

Runs step3 of linux.sh and the manual procedure in README.md with busybox sh.
Git fetches from a local bare repository instead of GitHub (see conftest.py).
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

from conftest import Remote, git, read_tree, write

HERE = Path(__file__).resolve().parent
LINUX_SH = HERE.parent / "linux.sh"
README = HERE.parents[1] / "README.md"

BUSYBOX = shutil.which("busybox")
pytestmark = pytest.mark.skipif(not BUSYBOX, reason="busybox is required to run shell scripts")

REMOTE_FILES = {
    ".bashrc": "remote bashrc\n",
    ".config/app/settings": "remote settings\n",
    ".profile": "same\n",
    "README.md": "remote readme\n",
}
LOCAL_FILES = {
    ".bashrc": "local bashrc\n",
    ".config/app/settings": "local settings\n",
    ".profile": "same\n",
    ".untracked": "untracked\n",
}
# Files that differ from the repository are backed up, but ones that are identical or untracked are not
BACKED_UP_FILES = {".bashrc": "local bashrc\n", ".config/app/settings": "local settings\n"}


@pytest.fixture
def home(tmp_path: Path) -> Path:
    path = tmp_path / "home"
    path.mkdir()
    return path


def run_sh(script: str, env: dict[str, str], fails: bool = False) -> subprocess.CompletedProcess:
    process = subprocess.run(
        [BUSYBOX, "sh", "-c", script],
        env=env,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
        timeout=120,
    )
    assert (process.returncode != 0) == fails, process
    return process


def run_linux_sh(remote: Remote, home: Path, answer: str = "n", fails: bool = False) -> subprocess.CompletedProcess:
    """Run step3 of linux.sh. `answer` is the reply to the backup confirmation."""
    # NOTE: linux.sh only defines functions when it has arguments.
    #       `confirm` is replaced because it reads /dev/tty, which busybox on Windows does not have.
    #       Pass the remote path instead of GITHUB_URL, because `git remote get-url` expands insteadOf
    return run_sh(
        'set -- 0\n. "$TEST_LINUX_SH"\nconfirm() { [ "$TEST_ANSWER" = y ]; }\nstep3 "$TEST_REMOTE" "$TEST_LOCAL"\n',
        {
            **remote.env,
            "TEST_LINUX_SH": LINUX_SH.as_posix(),
            "TEST_ANSWER": answer,
            "TEST_REMOTE": remote.path.as_posix(),
            "TEST_LOCAL": home.as_posix(),
        },
        fails,
    )


def run_readme(remote: Remote, home: Path) -> subprocess.CompletedProcess:
    env = {**remote.env, "HOME": str(home)}
    script = re.search(r"^```bash\n(.*?)^```", README.read_text(encoding="utf-8"), re.MULTILINE | re.DOTALL)[1]

    # Guard against overlaying the real home directory
    pwd = subprocess.run(
        [BUSYBOX, "sh", "-c", "cd && pwd"], env=env, capture_output=True, text=True, check=True
    ).stdout.strip()
    assert os.path.samefile(pwd, home), pwd

    return run_sh(f"set -e\ninit-dotfiles() {{ :; }}\n{script}", env)


INSTALLERS = {
    "linux.sh": lambda remote, home: run_linux_sh(remote, home, answer="y"),
    "README.md": run_readme,
}


def read_backups(home: Path) -> dict[str, str]:
    """Files under .orig/<time>/ as {original path: content}."""
    return {
        name: text
        for backup_dir in (home / ".orig").glob("*")
        for name, text in read_tree(backup_dir).items()
    }


def rev_parse(repo: Path, *args: str, remote: Remote) -> str:
    return git("-C", str(repo), "rev-parse", *args, env=remote.env)


def assert_tracks_origin_main(home: Path, remote: Remote) -> None:
    assert rev_parse(home, "--abbrev-ref", "HEAD", "@{upstream}", remote=remote) == "main\norigin/main"
    assert git("-C", str(home), "symbolic-ref", "--short", "refs/remotes/origin/HEAD", env=remote.env) == "origin/main"
    assert rev_parse(home, "HEAD", remote=remote) == rev_parse(remote.path, "main", remote=remote)
    assert git("-C", str(home), "status", "--porcelain", "--untracked-files=no", env=remote.env) == ""


@pytest.mark.parametrize("install", INSTALLERS.values(), ids=INSTALLERS.keys())
def test_overlays_repository_and_backs_up_conflicting_files(remote, home, install):
    remote.push(REMOTE_FILES)
    for name, text in LOCAL_FILES.items():
        write(home / name, text)

    install(remote, home)

    assert read_tree(home, skip=(".git", ".orig")) == {**REMOTE_FILES, ".untracked": "untracked\n"}
    assert read_backups(home) == BACKED_UP_FILES
    assert_tracks_origin_main(home, remote)


def test_linux_sh_does_not_ask_when_nothing_conflicts(remote, home):
    remote.push(REMOTE_FILES)
    write(home / ".untracked", "untracked\n")

    # NOTE: The default answer is "n", so this fails if linux.sh asks
    run_linux_sh(remote, home)

    assert read_tree(home, skip=(".git",)) == {**REMOTE_FILES, ".untracked": "untracked\n"}
    assert not (home / ".orig").exists()
    assert_tracks_origin_main(home, remote)


def test_linux_sh_checks_out_branch_when_repository_is_initialized_on_another_branch(remote, home):
    remote.push(REMOTE_FILES)
    git("init", "--quiet", "--initial-branch", "master", str(home), env=remote.env)
    git("-C", str(home), "remote", "add", "origin", remote.path.as_posix(), env=remote.env)

    run_linux_sh(remote, home)

    assert read_tree(home, skip=(".git",)) == REMOTE_FILES
    assert_tracks_origin_main(home, remote)


def test_linux_sh_aborts_when_backup_is_declined_and_can_be_retried(remote, home):
    remote.push(REMOTE_FILES)
    write(home / ".bashrc", "local bashrc\n")

    process = run_linux_sh(remote, home, answer="n", fails=True)

    assert "Aborted" in process.stdout
    assert read_tree(home, skip=(".git", ".orig")) == {".bashrc": "local bashrc\n"}
    # NOTE: HEAD is not created until the files are checked out, so the next run does the same procedure
    assert subprocess.run(
        ["git", "-C", str(home), "rev-parse", "--verify", "--quiet", "HEAD"], env=remote.env, capture_output=True
    ).returncode != 0

    run_linux_sh(remote, home, answer="y")

    assert read_tree(home, skip=(".git", ".orig")) == REMOTE_FILES
    assert read_backups(home) == {".bashrc": "local bashrc\n"}
    assert_tracks_origin_main(home, remote)


def test_linux_sh_fast_forwards_repository(remote, home):
    remote.push(REMOTE_FILES)
    run_linux_sh(remote, home)

    run_linux_sh(remote, home)

    assert_tracks_origin_main(home, remote)

    remote.push({".bashrc": "remote bashrc 2\n"})

    run_linux_sh(remote, home)

    assert read_tree(home, skip=(".git", ".orig")) == {**REMOTE_FILES, ".bashrc": "remote bashrc 2\n"}
    assert_tracks_origin_main(home, remote)


def test_linux_sh_refuses_to_update_with_uncommitted_changes(remote, home):
    remote.push(REMOTE_FILES)
    run_linux_sh(remote, home)
    remote.push({".bashrc": "remote bashrc 2\n"})
    write(home / ".config/app/settings", "local change\n")
    before = rev_parse(home, "HEAD", remote=remote)

    process = run_linux_sh(remote, home, fails=True)

    assert "Uncommitted changes" in process.stdout
    assert read_tree(home, skip=(".git", ".orig")) == {**REMOTE_FILES, ".config/app/settings": "local change\n"}
    assert rev_parse(home, "HEAD", remote=remote) == before


def test_linux_sh_refuses_other_repository(remote, home):
    remote.push(REMOTE_FILES)
    write(home / ".bashrc", "other bashrc\n")
    git("init", "--quiet", str(home), env=remote.env)
    git("-C", str(home), "remote", "add", "origin", "https://example.invalid/other.git", env=remote.env)

    process = run_linux_sh(remote, home, answer="y", fails=True)

    assert "Unexpected remote URL" in process.stdout
    assert read_tree(home, skip=(".git",)) == {".bashrc": "other bashrc\n"}
    assert not (home / ".orig").exists()
