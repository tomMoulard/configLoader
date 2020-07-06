#!/bin/bash
# ${HOME}/.xinitrc
# ┌─────────────────┐
# │╻ ╻╻┏┓╻╻╺┳╸┏━┓┏━╸│
# │┏╋┛┃┃┗┫┃ ┃ ┣┳┛┃  │
# │╹ ╹╹╹ ╹╹ ╹ ╹┗╸┗━╸│
# └─────────────────┘
# Maintainer:
#  tom at moulard dot org
# Complete_version:
#  You can file the updated version on the git repository
#  github.com/tommoulard/configloader


resources="$HOME/.Xresources /etc/X11/xinit/.Xresources"
# modmap="$HOME/.Xmodmap /etc/X11/xinit/.Xmodmap"

# $1: command to exec if the file exist
# $n: list of filenames
function apply(){
    BIN="$1"
    shift 1
    for resource in $@; do
        [[ -f $resource ]] && bash -c "$BIN $resource"
    done;
}

apply "xrdb -merge" $resources
# apply "xmodmap" $modmap

# exec /usr/local/bin/dwm
