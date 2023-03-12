# dotfiles

@03hcl's dotfiles

## notes

how to install in non-empty directory

```bash
cd

# git config --global --add user.name ***
# git config --global --add user.email ***@***

git init --initial-branch main
git commit --allow-empty -m "temp"

# git init
# git commit --allow-empty -m "temp"
# git branch -m master main

git remote add origin https://github.com/03hcl/dotfiles.git
git fetch origin
git branch -u origin/main main
git remote set-head origin main

mkdir .orig
mv .bashrc .orig
...

git reset --mixed origin/main
git checkout .

init-dotfiles
```
