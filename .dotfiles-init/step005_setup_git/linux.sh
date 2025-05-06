#!/usr/bin/env bash

set -euo pipefail

remove_git_paths() {
    for path in "$@"; do
        log "Path:   ${path}"
        if [ -f "${path}" ]; then
            rm "${path}"
            log " -> Removed."
        else
            log " -> Not found."
        fi
    done
}

update_git_config() {
    # mapfile -t paths < <(git var GIT_CONFIG_GLOBAL)
    paths=("${HOME}/.config/git/config" "${HOME}/.gitconfig")
    for path in "${paths[@]}"; do remove_git_paths "${path}"; done

    path="${paths[0]}"
    mkdir -p "$(dirname "${path}")"
    touch "${path}"

    git config --file "${path}" user.name "03"
    git config --file "${path}" user.email "kntaco03g1@gmail.com"
    git config --file "${path}" core.autocrlf input
    git config --file "${path}" core.editor "code --wait"
    git config --file "${path}" core.safecrlf true
    git config --file "${path}" init.defaultBranch main
    git config --file "${path}" rerere.enabled true

    log
    log_command git config --list --global
}

update_git_attributes() {
    # mapfile -t attrs < <(git var GIT_ATTR_GLOBAL)
    attrs=("${HOME}/.config/git/attributes" "${HOME}/.gitattributes")
    for attr in "${attrs[@]}"; do remove_git_paths "${attr}"; done

    src="$(dirname "${BASH_SOURCE:-"${0}"}")/.gitattributes"
    dst="${attrs[0]}"

    log
    copy_resource "${src}" "${dst}"
}

update_git_ignore() {
    src="$(dirname "${BASH_SOURCE:-"${0}"}")/.gitignore_global"
    dst="${HOME}/.config/git/ignore"

    copy_resource "${src}" "${dst}"
}

step5() {
    log_step 5 "Setup Git"

    update_git_config

    log
    log "------------------------------------------------------------------------"
    log

    update_git_attributes

    log
    log "------------------------------------------------------------------------"
    log

    update_git_ignore
}

# shellcheck source=/dev/null
. "$(git -C "$(realpath -es "$(dirname "${BASH_SOURCE:-"${0}"}")")" rev-parse --show-toplevel)/.dotfiles-init/linux_utils.sh" "0"

step5 "$@"
