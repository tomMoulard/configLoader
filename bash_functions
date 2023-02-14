#!/bin/bash
# $HOME/.bash_functions
# ┌────────────────────────────────────────┐
# │┏┓ ┏━┓┏━┓╻ ╻   ┏━╸╻ ╻┏┓╻┏━╸╺┳╸╻┏━┓┏┓╻┏━┓│
# │┣┻┓┣━┫┗━┓┣━┫   ┣╸ ┃ ┃┃┗┫┃   ┃ ┃┃ ┃┃┗┫┗━┓│
# │┗━┛╹ ╹┗━┛╹ ╹╺━╸╹  ┗━┛╹ ╹┗━╸ ╹ ╹┗━┛╹ ╹┗━┛│
# └────────────────────────────────────────┘
# Maintainer:
#  tom at moulard dot org
# Complete_version:
#  You can file the updated version on the git repository
#  github.com/tommoulard/configloader

# Extract the content of an achive
# Might replace with https://github.com/ouch-org/ouch
# alias extract="ouch decompress"
function extract() {
	if [ -z "$1" ]; then
		echo "Usage: ${FUNCNAME[0]} <path/file...>"
		return 1
	fi
	for n in "$@"; do
		if [ ! -f "${n}" ]; then
			echo "${FUNCNAME[0]}: '${n}': file does not exist"
			continue
		fi
		FTYPE="$(file "${n%,}" | awk '{print $2}')"
		case "${FTYPE}" in
		"compress'd") uncompress ./"${n}" ;; # compress -f <file*>
		7-zip) 7z x ./"${n}" ;;              # 7z a -t7z <archive.7z> <file*>
		Allegro) pack u "${n}" "${n}.out" ;; # pack <files> <file out>
		LZMA) unlzma ./"${n}" ;;             # lzma <file*>
		PE32) cabextract ./"${n}" ;;         # TODO
		RAR) unrar x -ad ./"${n}" ;;         # rar a -r <archive.rar> <file*>
		XZ) unxz ./"${n}" ;;                 # xz <file>
		Zip) unzip ./"${n}" ;;               # zip <archive.zip> <file*>
		bzip2) bunzip2 ./"${n}" ;;           # bzip2 <file*>
		gzip) tar xvf "${n}" ;;              # tar cfz <archive.tar> <file*>
		*)
			echo "${FUNCNAME[0]}: '${n}': '${FTYPE}' is a unknown archive method"
			continue
			;;
		esac
	done
}

function _disown() {
	bash -c "$1" >&/dev/null &
	disown $!
}

function dc() {
	docker-compose $(find . -name 'docker-compose*.yml' -type f -printf '%p\t%d\n' 2>/dev/null | sort -n -k2 | cut -f 1 | awk '{print "-f "$0}') "$@"
}

function upgrade() {
	apt list --upgradable
	for x in update upgrade; do
		sudo apt $x -y
	done
	sudo apt autoremove -y
	sudo snap refresh
}

# Removes spaces from a file name (can use globing)
# file\ with \spaces.py -> file-with-spaces.py
# file\ - \stuff.py -> file-stuff.py
function remove-spaces() {
	for INPUT in "$@"; do
		FILE="${INPUT// /-}"
		FILE="${FILE//+(-)/-}"
		mv "${INPUT}" "${FILE}"
		echo "${FILE}"
	done
}

function notify() {
	bash -c "$@"
	notify-send "Command is finished: ${?}" "$@"
}

# usage: go-download-version <version>
# example: go-download-version go1.19rc1
function go-download-version() {
	[[ -d "${HOME}/.local/opt/${1}" || -f "$(command -v "${1}")" ]] && echo "${1} already exists" && return
	mkdir -p "${HOME}/.local/opt/${1}"
	aria2c "https://go.dev/dl/${1}.linux-amd64.tar.gz" \
		--dir "${HOME}/.local/opt/${1}" \
		-o "${1}.linux-amd64.tar.gz" \
		|| (rm -fr "${HOME}/.local/opt/${1}" && echo "Failed to download ${1}" && return)
	tar xf "${HOME}/.local/opt/${1}/${1}.linux-amd64.tar.gz" --directory "${HOME}/.local/opt/${1}/"
	mv ${HOME}/.local/opt/${1}/go/* "${HOME}/.local/opt/${1}/"
	rm -r "${HOME}/.local/opt/${1}/go"
	ln -s "${HOME}/.local/opt/${1}/bin/go" "${HOME}/.local/bin/${1}"
}

}

# vim:ft=bash noet
