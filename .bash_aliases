#!/bin/bash

cdls() { builtin cd "$@" && clear && ll; }

alias cd="cdls"
alias less="less -iJKMNqRW -x4"

df-sort() { df -H -T | awk 'NR == 1 {print $0; next} {print $0 | "sort -k '"$1"'"}'; }
du1() { du -h -d 1 | sort -hr; }
rand() { tr -dc "$1" 2>/dev/null < "/dev/urandom" | head -c "$2"; }

alias df7="df-sort 7"
alias nemui="echo 'ねむい'"
alias rand0="rand 'a-z'"
alias rand1="rand 'a-zA-Z0-9'"
alias rand2="rand '#%+,./:=@_~a-zA-Z0-9-'"                  # without bash meta characters
alias rand3="rand '!#$%&()*+,./:;<=>?@[]^_{|}~a-zA-Z0-9-'"  # without spaces and " ' ` \
alias rand-all="rand '[:graph:]'"                           # without spaces
alias rand-base64="rand 'A-Za-z0-9+/'"

alias dc="DOCKER_BUILDKIT=1 docker compose"
alias d-c="DOCKER_BUILDKIT=1 docker-compose"

alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."
alias ......="cd ../../../../.."

if [ -f ~/.bash_aliases_local ]; then
    # shellcheck disable=SC1090
    . ~/.bash_aliases_local
fi
