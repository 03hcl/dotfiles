#!/bin/bash

cdls() {
    builtin cd "$@" && clear && ll;
}

alias cd='cdls'
alias less='less -iJKMNqRW -x4'
alias nemui='echo "ねむい"'

alias d+c='docker compose'
alias d-c='docker-compose'

alias ..='cd ..'
