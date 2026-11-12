# Setup

## Windows

Download and Install:

```powershell
iwr -useb "https://raw.githubusercontent.com/03hcl/dotfiles/refs/heads/main/.dotfiles-init/windows.ps1" | iex
```

Update:

```powershell
& "$HOME\.dotfiles\.dotfiles-init\windows.ps1"
```

Run through a specific step:

```powershell
# Download and execute
$env:DOTFILES_INIT_MAX_STEP = 1
iwr -useb "https://raw.githubusercontent.com/03hcl/dotfiles/refs/heads/main/.dotfiles-init/windows.ps1" | iex
Remove-Item Env:\DOTFILES_INIT_MAX_STEP

# Only execute
& "$HOME\.dotfiles\.dotfiles-init\windows.ps1" -MaxStep 1
```
