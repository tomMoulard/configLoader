# $HOME/.profile
# ┌───────────────────┐
# │┏━┓┏━┓┏━┓┏━╸╻╻  ┏━╸│
# │┣━┛┣┳┛┃ ┃┣╸ ┃┃  ┣╸ │
# │╹  ╹┗╸┗━┛╹  ╹┗━╸┗━╸│
# └───────────────────┘
# Maintainer:
#  tom at moulard dot org
# Complete_version:
#  You can file the updated version on the git repository
#  github.com/tommoulard/configloader
# Description:
#  ~/.profile: executed by the command interpreter for login shells.
#  This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
#  exists.
#  see /usr/share/doc/bash/examples/startup-files for examples.
#  the files are located in the bash-doc package.

# the default umask is set in /etc/profile; for setting the umask
# for ssh logins, install and configure the libpam-umask package.
#umask 022

# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
        source "$HOME/.bashrc"
    fi
fi

# set PATH so it includes user's private bin if it exists
PATHS="$HOME/bin $HOME/.scripts"
IFS=" ";for x in $PATHS; do
if [ -d "$x" ] ; then
    PATH="$x:$PATH"
fi
done

if [ -z "$SSH_AUTH_SOCK" ] ; then
    eval "$(ssh-agent -s)"
    ssh-add
fi

if [ "${DISPLAY}" != "" ]; then
    if [ -f "$HOME/.Xmodmap" ]; then
        xmodmap "$HOME/.Xmodmap"
    fi
    numlockx status | grep --quiet off && numlockx on # Enable numlock

    feh --bg-scale "${HOME}/workspace/configLoader/background/background.jpg"
    urxvtd -q -f -o
    xrdb -merge "${HOME}/.Xresources"
fi

# vim:ft=bash
