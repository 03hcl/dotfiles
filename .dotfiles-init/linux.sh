#!/usr/bin/env sh

set -eu

log() {
    time="$(date '+%Y-%m-%d %H:%M:%S.%3N %z' | sed -E 's/([+-][0-9]{2})([0-9]{2})$/(\1:\2)/')"
    case "${2:-INFO}" in
        TRACE)      color="37"; prefix="[TRACE]     ";;
        DEBUG)      color="36"; prefix="[DEBUG]     ";;
        INFO)       color="32"; prefix="[INFO]      ";;
        WARNING)    color="33"; prefix="[WARNING]   ";;
        ERROR)      color="31"; prefix="[ERROR]     ";;
        FATAL)      color="35"; prefix="[FATAL]     ";;
        *)          color="0";;
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
        if [ -z "${id}" ]; then
            return 1
        fi

        printf "%s" "$id"
        return 0
    fi

    return 1
}

get_version_codename() {
    if [ -f "/etc/os-release" ]; then
        # shellcheck source=/dev/null
        codename="$(. "/etc/os-release" && printf "%s" "${VERSION_CODENAME}")"
        if [ -z "${codename}" ]; then
            return 1
        fi

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
                software-properties-common \
                wget
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

update_local_repo() {
    remote="${1}"
    local="${2}"
    origin="${3}"
    branch="${4}"

    if [ ! -d "${local}/.git" ]; then return 1; fi
    if [ "$(git -C "${local}" remote get-url "${origin}" 2>/dev/null)" != "${remote}" ]; then return 1; fi
    actual_branch="$(git -C "${local}" branch --show-current 2>/dev/null)"
    if [ "${actual_branch}" != "${branch}" ]; then return 1; fi

    log " -> Update repository."
    git -C "${local}" fetch "${origin}" "${branch}"
    git -C "${local}" checkout --detach
    git -C "${local}" branch --force "${branch}" "${origin}/${branch}"
    git -C "${local}" switch "${branch}"
}

backup_directory() {
    local_repo="${1}"
    src="${2}"
    dst="${local_repo}-backup/$(date +%Y%m%d_%H%M%S)/$(basename "${src}")"

    log " -> Failed to update source directory. Backing up to target directory."
    log "        Source: ${src}"
    log "        Target: ${dst}"
    printf "Confirm backup? [y/N]: "
    read -r response

    if [ "${response}" != "y" ] && [ "${response}" != "Y" ]; then
        log " -> Aborted." "ERROR"
        exit 1
    fi

    log " -> Backup started."

    if [ -d "$(dirname "${dst}")" ]; then
        log " -> Failed to backup. Target directory already exists." "ERROR"
        exit 1
    else
        mkdir -p "$(dirname "${dst}")"
    fi

    mv "${src}" "${dst}"

    log " -> Backup completed."
}

backup_local_repo() { backup_directory "${1}" "${1}"; }

get_remote_repo() {
    remote="${1}"
    local="${2}"
    origin="${3}"
    branch="${4}"

    if [ -d "${local}" ]; then return; fi
    log " -> Clone repository."
    git clone "${remote}" "${local}" --origin "${origin}" --branch "${branch}"
}

step3() {
    remote="${1}"
    local="${2}"
    origin="${3:-origin}"
    branch="${4:-main}"

    log_step 3 "Clone 03hcl/dotfiles Repository"

    if [ -d "${local}" ]; then
        if ! update_local_repo "${remote}" "${local}" "${origin}" "${branch}"; then
            backup_local_repo "${local}"
        fi
    fi

    get_remote_repo "${remote}" "${local}" "${origin}" "${branch}"
}

enumerate_additional_steps() {
    steps_dir="${1}"

    if [ ! -d "$steps_dir" ]; then return; fi

    for dir in "$steps_dir"/step*; do
        [ -d "$dir" ] || continue
        script="$dir/linux.sh"
        [ -f "$script" ] || continue
        printf "%s\n" "$script"
    done
}

step4() {
    local="${1}"

    log_step 4 "Search Additional Steps"

    steps="$(enumerate_additional_steps "${local}/.dotfiles-init")"

    if [ -z "${steps}" ]; then
        log " -> No additional steps found."
        return
    fi

    count="$(printf "%s\n" "${steps}" | wc -l)"
    log " -> Found ${count} additional steps."

    for step in ${steps}; do
        # shellcheck source=/dev/null
        bash "${step}"
    done
}

initialize_dotfiles() {
    if [ $# -ne 0 ]; then return; fi

    log "Hello, Linux!"

    remote_repo_path="https://github.com/03hcl/dotfiles.git"
    local_repo_path="${HOME}/.dotfiles"

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
