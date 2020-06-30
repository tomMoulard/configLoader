# $HOME/.bashrc
# ┌──────────────────┐
# │┏┓ ┏━┓┏━┓╻ ╻┏━┓┏━╸│
# │┣┻┓┣━┫┗━┓┣━┫┣┳┛┃  │
# │┗━┛╹ ╹┗━┛╹ ╹╹┗╸┗━╸│
# └──────────────────┘
# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=-1
HISTFILESIZE=-1

# append to the history file, don't overwrite it
shopt -s histappend

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

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
  if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
    # We have color support; assume it's compliant with Ecma-48
    # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
    # a case would tend to support setf rather than setaf.)
    color_prompt=yes
  else
    color_prompt=
  fi
fi

# get current branch in git repo
function parse_git_branch() {
  BRANCH="$(git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/')"
  if [ ! "$BRANCH" == "" ]; then
    STAT="$(parse_git_dirty)"
    if [[ "$STAT" == "" ]]; then
      printf "$(tput setaf 2)[$BRANCH]$(tput setaf 0)"
    else
      echo "$(tput setaf 2)[$BRANCH$STAT$(tput setaf 2)]$(tput setaf 0)"
    fi
  else
    echo ""
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
    bits="$(tput setaf 2)>${bits}"
  fi
  if [ "${ahead}" == "0" ]; then
    bits="$(tput setaf 2)*${bits}"
  fi
  if [ "${newfile}" == "0" ]; then
    bits="$(tput setaf 2)+${bits}"
  fi
  if [ "${untracked}" == "0" ]; then
    bits="$(tput setaf 2)?${bits}"
  fi
  if [ "${deleted}" == "0" ]; then
    bits="$(tput setaf 1)x${bits}"
  fi
  if [ "${dirty}" == "0" ]; then
    bits="$(tput setaf 1)!${bits}"
  fi
  if [ ! "${bits}" == "" ]; then
    echo " ${bits}"
  else
    echo ""
  fi
}

# Term look
PROMPT_COMMAND=prompt
prompt(){
  RETVAL=$?
  if [[ $RETVAL -ne 0 ]]; then
    RETVAL="$(tput setaf 1)${RETVAL}$(tput setaf 0) "
  else
    RETVAL=""
  fi

  # If id command returns zero, you have root access.
  if [ "$(id -u)" -eq 0 ];
  then # you are root, set red colour prompt
    PS1="${debian_chroot:+($debian_chroot)}\[$(tput bold)\]\[$(tput setaf 1)\]"
    PS1="${PS1}[\!]\u@\h:\W > \[$(tput sgr0)\]"
  else # normal
    PS1="${debian_chroot:+($debian_chroot)}${RETVAL}\[$(tput bold)\]"
    PS1="${PS1}\[\`parse_git_branch\`\]\[$(tput setaf 2)\][\!]\u@\h:"
    PS1="${PS1}\[$(tput setaf 4)\]\W\[$(tput setaf 5)\] > \[$(tput sgr0)\]"
  fi
}
# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    if [ -r "$HOME/.dircolors" ]; then
      eval "$(dircolors -b ~/.dircolors)"
    else
      eval "$(dircolors -b)"
    fi
    alias ls='ls --color=auto'
fi

# colored GCC warnings and errors
# export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# Alias definitions.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.
if [ -f ~/workspace/configLoader/bash_aliases ]; then
    source "$HOME/workspace/configLoader/bash_aliases"
fi

# functions definitions.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.
if [ -f ~/.bash_functions ]; then
    source "$HOME/.bash_functions"
fi

# enable programmable completion features (you don't need to enable
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

date >> ~/.terminalLogDate

# Allow not case sensitive autocompletion
bind 'set completion-ignore-case on'

export VISUAL=vim
export SHELL=bash
export EDITOR="$VISUAL"
export PAGER=less
export BROWSER=chromium

# COLORS
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
# Man page color
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;31m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;32m'

# Enable to have some scripts in the PATH
# https://github.com/tomMoulard/scripts
[ -d "$HOME/.scripts" ] && PATH="$PATH:$HOME/.scripts" # github.com/tommoulard/scripts
[ -d "$HOME/go/bin" ] && PATH="$PATH:$HOME/go/bin"     # https://golang.org/doc/code.html#Command
[ -d "$HOME/.local/bin" ] && PATH="$PATH:$HOME/.local/bin"
if [[ -d "$HOME/.cargo/bin" ]]; then
  PATH="$PATH:$HOME/.cargo/bin"
  [ -f "$HOME/.cargo/bin/zoxide" ] && eval "$(zoxide init bash)" && alias cd='z' && _ZO_DATA_DIR=$HOME/.local/share/zoxide.db
fi

PATH=$PATH:/usr/local/go/bin

# GPG agent
GPG_TTY=$(tty)
export GPG_TTY

complete -C /home/tm/go/bin/mc mc

# enable gnome keyring
eval `gnome-keyring-daemon --start`
export SSH_AUTH_SOCK="$(ls /run/user/$(id -u $USERNAME)/keyring*/ssh|head -1)"
export SSH_AGENT_PID="$(pgrep gnome-keyring)"
