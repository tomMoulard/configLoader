#!/bin/bash

## How to
# git clone http://github.com/tommoulard/configLoader.git $HOME/.config
USAGE="Usage ${0}
Option:
\t-d,--debug\tActivate debug mode
\t-v,--verbose\tActivate verbose mode
\t-h,--help\tShow this help"

while [[ "${1}" != "" ]]; do
	case "${1}" in
	-d | --debug)
		set -x
		;;
	-v | --verbose)
		VERBOSE=true
		;;
	-h | --help)
		echo -e "${USAGE}"
		exit 0
		;;
	esac
	shift
done

# createLink create a link between the file in the git repo and the output file
# $1 must be the file path
# $2 must be the test $(man test) shellcheck SC1073,SC1072,SC1009
# $3 must be the output file path
function createLink() {
	if [ -L "${3}" ]; then
		rm -r "${3}"
	fi
	if [ "${2}" "${3}" ]; then
		mv "${3}" "${3}.$(date +"%y%m%d%H%M%S").old"
	fi
	[ "${VERBOSE}" == "true" ] && echo ln -s "${PWD}/${1}" "${3}"
	ln -s "${PWD}/${1}" "${3}"
}

# Background picture
timeout 5 wget -q https://tom.moulard.org/picts/background.jpg -O background/background.jpg

# Profile
createLink profile -f "${HOME}/.profile"

# Xressourses
createLink Xresources -f "${HOME}/.Xresources"
[[ -f /usr/bin/xrdb ]] && bash -c "/usr/bin/xrdb ${HOME}/.Xresources"

# Font
createLink fonts -d "${HOME}/.fonts"

# Vim
createLink vimrc -f "${HOME}/.vimrc"
createLink vim -d "${HOME}/.vim"

# SSH
createLink ssh -d "${HOME}/.ssh"

# Bash
createLink bashrc -f "${HOME}/.bashrc"
createLink bash_aliases -f "${HOME}/.bash_aliases"
createLink bash_functions -f "${HOME}/.bash_functions"

# Rxvt
createLink urxvt -d "${HOME}/.urxvt"

# xinitrc
createLink xinitrc -f "${HOME}/.xinitrc"

# gdbinit
createLink gdbinit -f "${HOME}/.gdbinit"

# xmodmap
createLink Xmodmap -f "${HOME}/.Xmodmap"

# dig
createLink digrc -f "${HOME}/.digrc"

# inputrc
createLink inputrc -f "${HOME}/.inputrc"

# gesture
mkdir -p "${HOME}/.config/fusuma/"
createLink fusuma.yml -f "${HOME}/.config/fusuma/config.yml"

# config
mkdir -p "${HOME}/.config/"
for FOLDER in config/*; do
	createLink "${FOLDER}" -d "${HOME}/.${FOLDER}"
done

# curl
createLink curlrc -f "${HOME}/.curlrc"

# git config
createLink gitconfig -f "${HOME}/.gitconfig"
git config --global core.excludesfile "${HOME}/workspace/configLoader/gitignore"
