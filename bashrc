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
*) return ;;
esac

# History {{{1
# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000000
HISTFILESIZE=1000000

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
# export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_so=$'\E[48;5;127m' # purple find
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
#
# Regular Colors
COLOR_OFF="\033[0m"     # Text Reset
BLACK="\[\033[1;30m\]"  # Black
RED="\[\033[1;31m\]"    # Red
GREEN="\[\033[1;32m\]"  # Green
YELLOW="\[\033[1;33m\]" # Yellow
BLUE="\[\033[1;34m\]"   # Blue
PURPLE="\[\033[1;35m\]" # Purple
CYAN="\[\033[1;36m\]"   # Cyan
WHITE="\[\033[1;37m\]"  # White

BLACK="$(tput setaf 0)"  # Black
RED="$(tput setaf 1)"    # Red
GREEN="$(tput setaf 2)"  # Green
YELLOW="$(tput setaf 3)" # Yellow
BLUE="$(tput setaf 4)"   # Blue
PURPLE="$(tput setaf 5)" # Purple
CYAN="$(tput setaf 6)"   # Cyan
WHITE="$(tput setaf 7)"  # White
# }}}

# VAR identification {{{2
# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
	debian_chroot=$(cat /etc/debian_chroot)
fi

# Git repo status {{{2
# get current branch in git repo
function parse_git_branch() {
	BRANCH="$(git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/')"
	if [ ! "${BRANCH}" == "" ]; then
		echo -e "${GREEN}[${BRANCH}$(parse_git_dirty)${GREEN}]${COLOR_OFF}"
	fi
}

# get current status of git repo
function parse_git_dirty() {
	STATUS=$(git status 2>&1 | tee)
	function _grep_git_status() {
		if [[ "${STATUS}" == *"${1}"* ]]; then
			echo "${2}"
		fi
	}
	BITS="${GREEN}$(_grep_git_status "renamed:" ">")${COLOR_OFF}"
	BITS+="${GREEN}$(_grep_git_status "Your branch is ahead of" "*")${COLOR_OFF}"
	BITS+="${GREEN}$(_grep_git_status "new file:" "+")${COLOR_OFF}"
	BITS+="${GREEN}$(_grep_git_status "Untracked files" "?")${COLOR_OFF}"
	BITS+="${RED}$(_grep_git_status "deleted:" "x")${COLOR_OFF}"
	BITS+="${RED}$(_grep_git_status "modified:" "!")${COLOR_OFF}"
	echo "${BITS}"
}
# }}}

# Prompt {{{2
PROMPT_COMMAND=prompt
prompt() {
	RETVAL=$?
	if [[ $RETVAL -ne 0 ]]; then
		RETVAL="\[${RED}\]${RETVAL}\[${COLOR_OFF}\] "
	else
		RETVAL=""
	fi
	# GIT_BRANCH="$(parse_git_branch) "

	# Set terminal title
	GIT_BRANCH="$(git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ - \1/')"
	PS1="\\[\\033]0;\\w${GIT_BRANCH}\\007\\]"

	# If id command returns zero, you have root access.
	if [ "$(id -u)" -eq 0 ]; then
		PS1="${PS1}\[${debian_chroot}\]\[${GREEN}\]"
		PS1="\[${PS1}[\!]\u@\h:\W > \[${COLOR_OFF}\]\[$(tput sgr0)\]"
		PS1="\[${PS1}\]"
	else # normal
		# PS1+="\\[${debian_chroot}\\]\\[${RETVAL}\\]"
		# PS1="\\[${PS1}\\]$(parse_git_branch)\\[${GREEN}\\][\!]\u@\h:"
		# PS1="\\[${PS1}\\]\\[${BLUE}\\]\W\\[${PURPLE}\\] > "
		# PS1="\\[${PS1}\\]\\[${COLOR_OFF}\\]\\[$(tput sgr0)\\]"
		# PS1="\\[${PS1}\\]"
		PS1+="${RETVAL}"
		# PS1+="${GIT_BRANCH}"
		PS1+="\[${BLUE}\]\W \[${COLOR_OFF}\]"
		PS1+="\[${PURPLE}\]> \[${COLOR_OFF}\]"
	fi
	export PS1

	PS2="\\[${YELLOW}\\]→ \\[${COLOR_OFF}\\]"
	export PS2
}
# }}}
# }}}

# enable color support {{{1
if [ -x /usr/bin/dircolors ]; then
	if [ -r "${HOME}/.dircolors" ]; then
		eval "$(dircolors -b "${HOME}/.dircolors")"
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
if [ -f "${HOME}/workspace/configLoader/bash_aliases" ]; then
	source "${HOME}/workspace/configLoader/bash_aliases"
fi
# }}}

# Functions {{{1
# functions definitions.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.
if [ -f "${HOME}/.bash_functions" ]; then
	source "${HOME}/workspace/configLoader/bash_functions"
fi
# }}}

# Autocompletion {{{1
# Enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
	[ -r /usr/share/bash-completion ] && source /usr/share/bash-completion/*
	[ -r /etc/bash_completion.d ] && source /etc/bash_completion.d/*
	[ -r /etc/bash_completion ] && source /etc/bash_completion
fi

if type brew &>/dev/null; then
	export HOMEBREW_PREFIX="$(brew --prefix)"
	export BASH_COMPLETION_COMPAT_DIR="/opt/homebrew/etc/bash_completion.d/"
	if [[ -r "${HOMEBREW_PREFIX}/etc/profile.d/bash_completion.sh" ]]; then
		source "${HOMEBREW_PREFIX}/etc/profile.d/bash_completion.sh"
	fi
fi

# Allow not case sensitive autocompletion
bind 'set completion-ignore-case on'

# Enter completion when tab
bind 'set show-all-if-ambiguous on'
bind 'TAB:menu-complete'

# Minio Completion
[ -f "/home/tm/go/bin/mc" ] && complete -C ${HOME}/go/bin/mc mc

# kubectl autocomplete
[ -f "$(command -v kubectl)" ] && source <(kubectl completion bash)

# Custom autocompletions (docker-compose, ...)
[ -d "${HOME}/workspace/configLoader/bash_completion" ] && source "${HOME}"/workspace/configLoader/bash_completion/*

# terraform autocomplete
[ -f "$(command -v terraform)" ] && complete -C "$(command -v terraform)" terraform && complete -C "$(command -v terraform)" t
# }}}

# Loggin {{{1
date >>"${HOME}/.terminalLogDate"
# }}}

# macos stuff {{{2
[ -d "/opt/homebrew/bin" ] && PATH=$PATH:/opt/homebrew/bin
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
export CPPFLAGS="-I/opt/homebrew/opt/openjdk/include"
# }}}

# Reverse History search (<ctrl>-r) {{{1
[ -f "$(command -v fzf)" ] && source /usr/share/doc/fzf/examples/key-bindings.bash
# }}}

# Custom ENV var {{{1
if [ -f "${HOME}/workspace/configLoader/.env" ]; then
	set -o allexport
	source "${HOME}/workspace/configLoader/.env"
	set +o allexport
fi
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
	[ -f "${HOME}/.cargo/env" ] && source "${HOME}/.cargo/env"
	# Zoxide https://github.com/ajeetdsouza/zoxide can be replaced by CDPATH
	[[ "${CDPATH}" == "" && -f "${HOME}/.cargo/bin/zoxide" ]] && eval "$(zoxide init bash)" && alias cd='z' && export _ZO_DATA_DIR="${HOME}/.local/share/zoxide.db"
	# Exa https://github.com/ogham/exa
	[ -f "$(command -v exa)" ] && alias ls='exa'
fi
# }}}
# }}}

# GPG agent {{{1
[ -f "$(command -v tty)" ] && GPG_TTY=$(tty) export GPG_TTY
# }}}

# gnome keyring {{{1
[ -f "$(command -v gnome-keyring-daemon)" ] && eval "$(gnome-keyring-daemon --start)"
[[ -f "$(command -v id)" && -f "/run/user" ]] && SSH_AUTH_SOCK="$(find /run/user/"$(id -u "${USERNAME:-root}")"/keyring*/ssh | head -1)" && export SSH_AUTH_SOCK="${SSH_AUTH_SOCK?}"
[ -f "$(command -v pgrep)" ] && SSH_AGENT_PID="$(pgrep gnome-keyring)" && export SSH_AGENT_PID="${SSH_AGENT_PID?}"
# }}}

# nvim {{{1
[ -d "${HOME}/.local/share/nvim/bin" ] && PATH="$PATH:${HOME}/.local/share/nvim/bin"

# ghostty {{{1
# Ghostty shell integration for Bash. This must be at the top of your bashrc!
if [ -n "${GHOSTTY_RESOURCES_DIR}" ]; then
    builtin source "${GHOSTTY_RESOURCES_DIR}/shell-integration/bash/ghostty.bash"
fi
# }}}

[[ -r "/opt/homebrew/etc/profile.d/bash_completion.sh" ]] && . "/opt/homebrew/etc/profile.d/bash_completion.sh"

# vim: fdm=marker noet
