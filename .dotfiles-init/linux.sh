#!/usr/bin/env sh

set -eu

confirm() {
    # NOTE: Read from the terminal because stdin can be a pipe (e.g. `git ls-files | while`, `curl | sh`)
    printf "%s [y/N]: " "${1}" >/dev/tty
    IFS= read -r response </dev/tty || return 1

    [ "${response}" = "y" ] || [ "${response}" = "Y" ]
}

log() {
    time="$(date '+%Y-%m-%d %H:%M:%S.%3N %z' | sed -E 's/([+-][0-9]{2})([0-9]{2})$/(\1:\2)/')"
    case "${2:-INFO}" in
        TRACE)      color="37"; prefix="[TRACE]     ";;
        DEBUG)      color="36"; prefix="[DEBUG]     ";;
        INFO)       color="32"; prefix="[INFO]      ";;
        WARNING)    color="33"; prefix="[WARNING]   ";;
        ERROR)      color="31"; prefix="[ERROR]     ";;
        FATAL)      color="35"; prefix="[FATAL]     ";;
        *)          color="0";  prefix="[UNKNOWN]   ";;
    esac

    printf "%b" "${1:- }" | while IFS= read -r line || [ -n "${line}" ]; do
        printf "\033[90m%s\033[0m    \033[%sm%s\033[0m%s\n" "${time}" "${color}" "${prefix}" "${line}"
    done
}

log_step() {
    log
    log "========================================================================"
    log "Step ${1}: ${2}"
    log "========================================================================"
    log
}

log_command() {
    log "------------------------------------------------------------------------"
    log " -> Command: $*"
    log "------------------------------------------------------------------------"
    log

    if out="$("$@" 2>&1)"; then
        log "${out}" "INFO"
    else
        log "${out}" "ERROR"
    fi

    log
}

get_distro() {
    if [ -f "/etc/os-release" ]; then
        # shellcheck source=/dev/null
        id="$(. "/etc/os-release" && printf "%s" "${ID}")"
        [ -n "${id}" ] || return 1

        printf "%s" "$id"
        return 0
    fi

    return 1
}

get_version_codename() {
    if [ -f "/etc/os-release" ]; then
        # shellcheck source=/dev/null
        codename="$(. "/etc/os-release" && printf "%s" "${VERSION_CODENAME}")"
        [ -n "${codename}" ] || return 1

        printf "%s" "$codename"
        return 0
    fi

    return 1
}

get_temp_dir() {
    temp_dir="/tmp/.dotfiles-init"
    mkdir -p "${temp_dir}"
    printf "%s" "${temp_dir}"
}

step1() {
    log_step 1 "Show Environment Information"

    log_command uname -a
    log_command cat /etc/os-release
    log_command hostname
    log_command env
}

# NOTE: https://github.com/git/git/blob/master/INSTALL
# install_git_from_source() {
#     version="${1}"

#     url="https://www.kernel.org/pub/software/scm/git/git-${version}.tar.xz"
#     dir="$(get_temp_dir)/git-${version}"

#     curl -L "${url}" | tar -xJf - --strip-components=1 -C "${dir}"
#     # apt install ...
#     make prefix="${HOME}/.local/bin"
#     make prefix="${HOME}/.local/bin" install
# }

install_base_packages() {
    case "$(get_distro)" in
        debian)
            sudo apt update
            sudo apt upgrade
            sudo apt install \
                bash \
                ca-certificates \
                curl \
                git \
                wget
                # software-properties-common
            codename="$(get_version_codename)"
            cat << EOF | sudo tee "/etc/apt/sources.list.d/dotfiles-init.sources"
Types:          deb
URIs:           http://deb.debian.org/debian
Suites:         ${codename}-backports testing unstable
Components:     main contrib non-free non-free-firmware
Signed-By:      /usr/share/keyrings/debian-archive-keyring.gpg
Enabled:        yes
EOF
            cat << EOF | sudo tee "/etc/apt/preferences.d/99-dotfiles-init.pref"
Package: *
Pin: release a=${codename}-backports
Pin-Priority: 100

Package: *
Pin: release a=testing
Pin-Priority: 100

Package: *
Pin: release a=unstable
Pin-Priority: 100
EOF
            sudo apt update
            sudo apt autoremove
            ;;
        *)
            return 1 ;;
    esac
}

step2() {
    log_step 2 "Install Latest Git Client"

    install_base_packages

    log_command git --version
}

backup_file() {
    src="${1}"
    dst="${2}"

    log " -> Back up existing file."
    log "        Source: ${src}"
    log "        Target: ${dst}"

    if ! confirm "Confirm backup?"; then
        log " -> Aborted." "ERROR"
        return 1
    fi

    [ ! -e "${dst}" ] && [ ! -L "${dst}" ] || return 1

    mkdir -p "$(dirname "${dst}")"
    mv "${src}" "${dst}"
}

init_local_repo() {
    remote_repo="${1}"
    local_repo="${2}"
    origin="${3}"
    branch="${4}"

    if [ ! -e "${local_repo}/.git" ] && [ ! -L "${local_repo}/.git" ]; then
        log " -> Initialize repository."
        git init --initial-branch="${branch}" "${local_repo}"
        git -C "${local_repo}" remote add "${origin}" "${remote_repo}"
    fi

    if [ ! -d "${local_repo}/.git" ] || [ -L "${local_repo}/.git" ]; then
        log " -> Unexpected '.git'. Expected a directory, not a symbolic link." "ERROR"
        log "        Path:     ${local_repo}/.git" "ERROR"
        return 1
    fi

    actual_remote_repo="$(git -C "${local_repo}" remote get-url "${origin}")"
    if [ "${actual_remote_repo}" != "${remote_repo}" ]; then
        log " -> Unexpected remote URL." "ERROR"
        log "        Actual:   ${actual_remote_repo}" "ERROR"
        log "        Expected: ${remote_repo}" "ERROR"
        return 1
    fi

    git -C "${local_repo}" fetch "${origin}" "${branch}"

    if ! git -C "${local_repo}" rev-parse --verify HEAD >/dev/null 2>&1; then
        log " -> Checkout repository."

        git -C "${local_repo}" read-tree FETCH_HEAD
        git -C "${local_repo}" update-index -q --refresh

        backup_dir="${local_repo}/.orig/$(date +%Y%m%d_%H%M%S)_$$"

        git -C "${local_repo}" -c core.quotePath=false ls-files --modified | while IFS= read -r file; do
            src="${local_repo}/${file}"
            [ -e "${src}" ] || [ -L "${src}" ] || continue

            parent="$(dirname "${file}")"
            while [ "${parent}" != "." ]; do
                if [ -L "${local_repo}/${parent}" ]; then
                    log " -> Unexpected symbolic link in the parent directories." "ERROR"
                    log "        Path:     ${local_repo}/${parent}" "ERROR"
                    exit 1
                fi
                parent="$(dirname "${parent}")"
            done

            backup_file "${src}" "${backup_dir}/${file}"
        done

        git -C "${local_repo}" checkout-index -a
        git -C "${local_repo}" symbolic-ref HEAD "refs/heads/${branch}"
        git -C "${local_repo}" update-ref "refs/heads/${branch}" FETCH_HEAD
        git -C "${local_repo}" branch --set-upstream-to="${origin}/${branch}" "${branch}"
        git -C "${local_repo}" remote set-head "${origin}" "${branch}"
    else
        log " -> Update repository."

        remote_head="$(git -C "${local_repo}" rev-parse --verify 'FETCH_HEAD^{commit}')"
        git -C "${local_repo}" merge-base --is-ancestor "${remote_head}" HEAD && return 0

        actual_branch="$(git -C "${local_repo}" branch --show-current)"
        if [ "${actual_branch}" != "${branch}" ]; then
            log " -> Unexpected current branch." "ERROR"
            log "        Actual:   ${actual_branch}" "ERROR"
            log "        Expected: ${branch}" "ERROR"
            return 1
        fi

        if [ -n "$(git -C "${local_repo}" status --porcelain --untracked-files=no)" ]; then
            log " -> Uncommitted changes exist. Commit or stash them first." "ERROR"
            return 1
        fi

        git -C "${local_repo}" merge --ff-only --no-overwrite-ignore "${remote_head}"
    fi
}

step3() {
    remote_repo="${1}"
    local_repo="${2}"
    origin="${3:-origin}"
    branch="${4:-main}"

    log_step 3 "Clone 03hcl/dotfiles Repository"

    init_local_repo "${remote_repo}" "${local_repo}" "${origin}" "${branch}"
}

enumerate_additional_steps() {
    steps_dir="${1}"

    [ -d "${steps_dir}" ] || return 0

    for dir in "${steps_dir}"/step*; do
        [ -d "${dir}" ] || continue
        script="${dir}/linux.sh"
        [ -f "${script}" ] || continue
        printf "%s\n" "$script"
    done
}

step4() {
    local_repo="${1}"

    log_step 4 "Search Additional Steps"

    steps="$(enumerate_additional_steps "${local_repo}/.dotfiles-init")"

    if [ -z "${steps}" ]; then
        log " -> No additional steps found."
        return
    fi

    count="$(printf "%s\n" "${steps}" | wc -l)"
    log " -> Found ${count} additional steps."

    printf '%s\n' "${steps}" | while IFS= read -r step; do
        # shellcheck source=/dev/null
        bash "${step}"
    done
}

initialize_dotfiles() {
    [ $# -eq 0 ] || return 0

    log "Hello, Linux!"

    remote_repo_path="https://github.com/03hcl/dotfiles.git"
    local_repo_path="${HOME}"

    step1
    step2
    step3 "${remote_repo_path}" "${local_repo_path}"
    step4 "${local_repo_path}"

    log ""
    log "========================================================================"
    log "Successfully completed!"
    log "========================================================================"
}

initialize_dotfiles "$@"
