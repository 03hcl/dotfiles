#!/bin/bash

cdls() {
    builtin cd "$@" && clear && ll;
}

alias cd='cdls'
alias less='less -iJKMNqRW -x4'

df-sort() {
    df -H -T | awk 'NR == 1 {print $0; next} {print $0 | "sort -k '"$1"'"}';
}

alias df7="df-sort 7"
alias du1='du -h -d 1 | sort -hr'
alias nemui='echo "ねむい"'

alias d+c='DOCKER_BUILDKIT=1 docker compose'
alias d-c='DOCKER_BUILDKIT=1 docker-compose'

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ......='cd ../../../../..'

if [ -f ~/.bash_aliases_local ]; then
    # shellcheck disable=SC1090
    . ~/.bash_aliases_local
fi
