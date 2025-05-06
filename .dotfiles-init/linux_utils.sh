#!/usr/bin/env bash

# shellcheck source=/dev/null
. "$(git -C "$(realpath -es "$(dirname "${BASH_SOURCE:?}")")" rev-parse --show-toplevel)/.dotfiles-init/linux.sh" "0"

copy_resource() {
    src="$(realpath -es "${1}")"
    dst="$(realpath -s "${2}")"

    log "Copy '${src}' ..."
    log "    from:   ${src}"
    log "    to:     ${dst}"

    mkdir -p "$(dirname "${dst}")"
    cp -f "${src}" "${dst}"

    log " -> Copied."
}
