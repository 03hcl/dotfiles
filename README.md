# dotfiles

@03hcl's dotfiles

## notes

how to install in non-empty directory

```bash
cd

git init --initial-branch main
git remote add origin https://github.com/03hcl/dotfiles.git
git fetch origin
git reset --mixed origin/main
git branch -u origin/main main
git remote set-head origin main

backup=".orig/$(date +%Y%m%d_%H%M%S)"
git diff --name-only --diff-filter=M | while read f; do mkdir -p "$(dirname "$backup/$f")" && mv "$f" "$backup/$f"; done

git checkout .

init-dotfiles
```
