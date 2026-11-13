# Tests

<!-- markdownlint-disable MD013 -->

Tests are written in Python with [pytest](https://docs.pytest.org/).
Tests of PowerShell scripts run on every PowerShell found (`pwsh` and Windows PowerShell 5.1 `powershell`).
`step006_setup_powershell` also installs Pester 5 or later for both shells for future PowerShell-native tests; the current tests still use pytest.

Requirements:

- [uv](https://docs.astral.sh/uv/) (installed by `step009_install_python`)
- `git`
- `busybox` (installed by `step006_setup_powershell`) to run shell scripts; tests that need it are skipped without it

Run (takes a few minutes):

```powershell
uvx pytest .dotfiles-init\tests
```

If uv fails with `did not find executable at '...\.local\bin\python.exe'`, specify the Python:

```powershell
uvx --python (Get-Command python).Source pytest .dotfiles-init\tests
```

Add `-v` to list each test, or `-k <keyword>` to select tests (e.g. `-k dry_run`).
