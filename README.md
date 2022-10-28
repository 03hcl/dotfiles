# dotfiles

@03hcl's dotfiles

## notes

how to install in non-empty directory

```bash
cd
git init --initial-branch main
git commit --allow-empty -m "temp"

git remote add origin https://github.com/03hcl/dotfiles.git
git branch -u origin/main main
git remote set-head origin main
git fetch origin

mkdir .orig
mv .bashrc .orig
...

git reset --mixed origin/main
git checkout .
```
