#!/bin/bash

## How to
# git clone http://github.com/tommoulard/configLoader.git $HOME/.config
USAGE="Usage ${0}
Option:
\t-c,--config\tPromt user to enter configuration variables
\t-d,--debug\tActivate debug mode
\t-g,--gui\tUse GUI to help with the configuration (implies --config)
\t-h,--help\tShow this help
\t-v,--verbose\tActivate verbose mode"

WHIPTAIL="Welcome in the configuration wizzard of ConfigLoader.
Some file will be changed in order to have most of your configuration in one place: ${PWD}.
The use of links allow you to only have to modify files in this directory in order to change/update the configuration.
Thus, in order to update/maintain your configuration, go to this directory and update it.

Do you want to procede ?
"

while [[ "${1}" != "" ]]; do
	case "${1}" in
	-c | --config)
		FILL_CONFIG=true
		;;
	-d | --debug)
		set -x
		;;
	-g | --gui)
		FILL_CONFIG=true
		USE_GUI=true
		whiptail \
			--backtitle 'Configuration Loader' \
			--title "Welcome onboard" \
			--yesno "${WHIPTAIL}" 15 78 --defaultno ||
			exit 0
		;;
	-h | --help)
		echo -e "${USAGE}"
		exit 0
		;;
	-v | --verbose)
		VERBOSE=true
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

# replace_default promt user for a replace value for env vars
# $1 must be the thing to prompt (i.e. editor)
# $2 must be the default value (i.e. vim)
function replace_default() {
	if [ "${USE_GUI}" == "true" ]; then
		whiptail \
			--backtitle 'Configuration Loader' \
			--title "${1}" \
			--default-item "${2}" \
			--inputbox "Enter your ${1}" 10 30 "${2}" ||
			exit 1
	else
		read -p "Enter your ${1} [${2}]: " VAR
	fi
	sed -i "s/${2}/${VAR:=${2}}/" .env
}

if [ "${FILL_CONFIG}" == "true" ]; then
	cp .env.default .env
	replace_default "email" "changeme@example.com"
	replace_default "web brower" "google-chrome"
	replace_default "editor" "vim"
	replace_default "pager" "less"
	replace_default "terminal" "urxvtc"
	replace_default "name" "Your Name"
	# TODO: generate ssh/gpg key and fill configuration
	# gpg --gen-key
	# git config --global user.signingkey <key_id>
	# git config commit.gpgsign true
	source ~/.bashrc
fi

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

# vim: noet
