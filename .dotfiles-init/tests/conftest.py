"""Fixtures shared by the tests of the installers (linux.sh, README.md, windows.ps1)."""

from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass
from pathlib import Path

import pytest

GITHUB_URL = "https://github.com/03hcl/dotfiles.git"


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.encode("utf-8"))


def read_tree(root: Path, skip: tuple[str, ...] = (".git",)) -> dict[str, str]:
    """Files under root as {relative path: content}, except top-level entries in skip."""
    return {
        path.relative_to(root).as_posix(): path.read_bytes().decode("utf-8")
        for path in sorted(root.rglob("*"))
        if path.is_file() and path.relative_to(root).parts[0] not in skip
    }


def git(*args: str, env: dict[str, str]) -> str:
    return subprocess.run(
        ["git", *args], env=env, capture_output=True, encoding="utf-8", check=True
    ).stdout.strip()


@dataclass
class Remote:
    """Bare repository that stands in for GITHUB_URL."""

    path: Path
    work: Path
    env: dict[str, str]

    def push(self, files: dict[str, str]) -> None:
        for name, text in files.items():
            write(self.work / name, text)
        git("-C", str(self.work), "add", "--all", env=self.env)
        git("-C", str(self.work), "commit", "--quiet", "--message", "update", env=self.env)
        git("-C", str(self.work), "push", "--quiet", "origin", "main", env=self.env)


@pytest.fixture
def remote(tmp_path: Path) -> Remote:
    """Remote repository. `env` isolates git from the user's config and redirects GITHUB_URL to it."""
    path = tmp_path / "remote.git"
    work = tmp_path / "remote-work"
    config = tmp_path / "gitconfig"
    env = {**os.environ, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": str(config)}
    for key, value in [
        ("user.name", "test"),
        ("user.email", "test@example.invalid"),
        ("init.defaultBranch", "main"),
        (f"url.{path.as_posix()}.insteadOf", GITHUB_URL),
    ]:
        git("config", "--file", str(config), key, value, env=env)
    git("init", "--quiet", "--bare", str(path), env=env)
    git("clone", "--quiet", str(path), str(work), env=env)
    return Remote(path, work, env)
