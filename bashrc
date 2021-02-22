#!/bin/bash
# $HOME/.bashrc
# ┌──────────────────┐
# │┏┓ ┏━┓┏━┓╻ ╻┏━┓┏━╸│
# │┣┻┓┣━┫┗━┓┣━┫┣┳┛┃  │
# │┗━┛╹ ╹┗━┛╹ ╹╹┗╸┗━╸│
# └──────────────────┘
# Maintainer:
#  tom at moulard dot org
# Complete_version:
#  You can file the updated version on the git repository
#  github.com/tommoulard/configloader
# Description:
#  ~/.bashrc: executed by bash(1) for non-login shells.
#  see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
#  for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# History {{{1
# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=-1
HISTFILESIZE=-1

# append to the history file, don't overwrite it
shopt -s histappend
# }}}

# Input {{{1
# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# Enable extended globbing
shopt -s extglob

# save multi-line commands as a single history entry
shopt -s cmdhist

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
# shopt -s globstar

# Remove terminal suspend feature (<ctrl-s> and <ctrl-q>)
# stty -ixon
# }}}

# Less {{{1
# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# Man page color
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;31m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;32m'
# }}}

# Prompt {{{1

# COLORS {{{2
#   Attributes:   Text color:    Background:
#   0 reset all   30 black       40 black
#   1 bright      31 red         41 red
#   2 dim         32 green       42 green
#   4 underscore  33 yellow      43 yellow
#   5 blink       34 blue        44 blue
#   7 reverse     35 purple      45 purple
#   8 hidden      36 cyan        46 cyan
#                 37 white       47 white
# Separate with ";"
# Reset
COLOR_OFF="\033[0m"       # Text Reset

# Regular Colors
BLACK="\033[1;30m"        # Black
RED="\033[1;31m"          # Red
GREEN="\033[1;32m"        # Green
YELLOW="\033[1;33m"       # Yellow
BLUE="\033[1;34m"         # Blue
PURPLE="\033[1;35m"       # Purple
CYAN="\033[1;36m"         # Cyan
WHITE="\033[1;37m"        # White
# }}}

# VAR identification {{{2
# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "${TERM}" in
    xterm-color|*-256color) color_prompt=yes;;
esac
# }}}

# Git repo status {{{2
# get current branch in git repo
function parse_git_branch() {
    BRANCH="$(git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/')"
    if [ ! "${BRANCH}" == "" ]; then
        STAT="$(parse_git_dirty)"
        if [[ "${STAT}" == "" ]]; then
            echo -e "${GREEN}[${BRANCH}${GREEN}]${COLOR_OFF}"
        else
            echo -e "${GREEN}[${BRANCH}${STAT}${GREEN}]${COLOR_OFF}"
        fi
    fi
}

# get current status of git repo
function parse_git_dirty {
    status=$(git status 2>&1 | tee)
    dirty=$(echo -n "${status}" 2> /dev/null \
        | grep "modified:" &> /dev/null; echo "$?")
    untracked=$(echo -n "${status}" 2> /dev/null \
        | grep "Untracked files" &> /dev/null; echo "$?")
    ahead=$(echo -n "${status}" 2> /dev/null \
        | grep "Your branch is ahead of" &> /dev/null; echo "$?")
    newfile=$(echo -n "${status}" 2> /dev/null \
        | grep "new file:" &> /dev/null; echo "$?")
    renamed=$(echo -n "${status}" 2> /dev/null \
        | grep "renamed:" &> /dev/null; echo "$?")
    deleted=$(echo -n "${status}" 2> /dev/null \
        | grep "deleted:" &> /dev/null; echo "$?")
    bits=''
    if [ "${renamed}" == "0" ]; then
        bits="${GREEN}>${bits}${COLOR_OFF}"
    fi
    if [ "${ahead}" == "0" ]; then
        bits="${GREEN}*${bits}${COLOR_OFF}"
    fi
    if [ "${newfile}" == "0" ]; then
        bits="${GREEN}+${bits}${COLOR_OFF}"
    fi
    if [ "${untracked}" == "0" ]; then
        bits="${GREEN}?${bits}${COLOR_OFF}"
    fi
    if [ "${deleted}" == "0" ]; then
        bits="${RED}x${bits}${COLOR_OFF}"
    fi
    if [ "${dirty}" == "0" ]; then
        bits="${RED}!${bits}${COLOR_OFF}"
    fi
    if [ ! "${bits}" == "" ]; then
        echo " ${bits}"
    fi
}
# }}}

# Prompt {{{2
PROMPT_COMMAND=prompt
prompt(){
    RETVAL=$?
    if [[ $RETVAL -ne 0 ]]; then
        RETVAL="${RED}${RETVAL}${COLOR_OFF} "
    else
        RETVAL=""
    fi

    # Set terminal title
    PS1="\\[\\033]0;\\w\\007\\]";

    # If id command returns zero, you have root access.
    if [ "$(id -u)" -eq 0 ]; then
        PS1+="\[${debian_chroot:+($debian_chroot)}\[${GREEN}\]"
        PS1="\[${PS1}[\!]\u@\h:\W > \[${COLOR_OFF}\]\[$(tput sgr0)\]"
        PS1="\[${PS1}\]"
    else # normal
        PS1+="\\[${debian_chroot:+($debian_chroot)}\\]\\[${RETVAL}\\]"
        PS1="\\[${PS1}\\]$(parse_git_branch)\\[${GREEN}\\][\!]\u@\h:"
        PS1="\\[${PS1}\\]\\[${BLUE}\\]\W\\[${PURPLE}\\] > "
        PS1="\\[${PS1}\\]\\[${COLOR_OFF}\\]\\[$(tput sgr0)\\]"
        PS1="\\[${PS1}\\]"
    fi
    export PS1;

    PS2="\\[${YELLOW}\\]→ \\[${COLOR_OFF}\\]";
    export PS2;
}
# }}}
# }}}

# enable color support {{{1
if [ -x /usr/bin/dircolors ]; then
    if [ -r "$HOME/.dircolors" ]; then
      eval "$(dircolors -b ~/.dircolors)"
    else
      eval "$(dircolors -b)"
    fi
fi
# }}}

# GCC {{{1
# colored GCC warnings and errors
# export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'
# }}}

# Aliases {{{1
# Alias definitions.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.
if [ -f ~/workspace/configLoader/bash_aliases ]; then
    source "$HOME/workspace/configLoader/bash_aliases"
fi
# }}}

# Functions {{{1
# functions definitions.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.
if [ -f ~/.bash_functions ]; then
    source "$HOME/workspace/configLoader/bash_functions"
fi
# }}}

# Autocompletion {{{1
# Enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion ]; then
    source /usr/share/bash-completion/*
  fi
  if [ -f /etc/bash_completion.d ]; then
    source /etc/bash_completion.d/*
  fi
  if [ -f /etc/bash_completion ]; then
    source /etc/bash_completion
  fi
fi

# Allow not case sensitive autocompletion
bind 'set completion-ignore-case on'

# Minio Completion
complete -C /home/tm/go/bin/mc mc
# }}}

# Loggin {{{1
date >> ~/.terminalLogDate
# }}}

# Custom ENV var {{{1
export VISUAL=vim
export SHELL=bash
export EDITOR="$VISUAL"
export PAGER=less
export BROWSER=google-chrome
# }}}

# Custom bin PATH {{{1
# Enable to have some scripts in the PATH
# https://github.com/tomMoulard/scripts
[ -d "${HOME}/.scripts" ] && PATH="$PATH:${HOME}/.scripts" # github.com/tommoulard/scripts
[ -d "${HOME}/go/bin" ] && PATH="$PATH:${HOME}/go/bin"     # https://golang.org/doc/code.html#Command
[ -d "${HOME}/.local/bin" ] && PATH="$PATH:${HOME}/.local/bin"
[ -d "/usr/local/go/bin" ] && PATH=$PATH:/usr/local/go/bin
[ -d "${HOME}/.local/opt/go/bin" ] && PATH=$PATH:${HOME}/.local/opt/go/bin

# Cargo stuff {{{2
if [[ -d "${HOME}/.cargo/bin" ]]; then
  PATH="$PATH:${HOME}/.cargo/bin"
  # Zoxide https://github.com/ajeetdsouza/zoxide
  [ -f "${HOME}/.cargo/bin/zoxide" ] && eval "$(zoxide init bash)" && alias cd='z' && _ZO_DATA_DIR="${HOME}/.local/share/zoxide.db"
  # Exa https://github.com/ogham/exa
  ([ -f "${HOME}/.cargo/bin/exa" ] || [ -f "$(which exa)" ]) && alias ls='exa'
fi
# }}}
# }}}

# GPG agent {{{1
GPG_TTY=$(tty)
export GPG_TTY
# }}}

# gnome keyring {{{1
eval "$(gnome-keyring-daemon --start)"
SSH_AUTH_SOCK="$(find /run/user/"$(id -u "${USERNAME}")"/keyring*/ssh|head -1)"
SSH_AGENT_PID="$(pgrep gnome-keyring)"
export SSH_AUTH_SOCK="${SSH_AUTH_SOCK?}" SSH_AGENT_PID="${SSH_AGENT_PID?}"
# }}}

# vim: fdm=marker
source "$HOME/.cargo/env"
