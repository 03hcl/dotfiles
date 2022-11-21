#!/bin/bash

cdls() {
    builtin cd "$@" && clear && ll;
}

alias cd='cdls'
alias less='less -iJKMNqRW -x4'

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
    . ~/.bash_aliases_local
fi
