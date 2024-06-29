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

function upgrade() {
	set -x
	apt list --upgradable
	snap refresh --list
	for x in update upgrade dist-upgrade; do
		sudo apt $x -y
	done
	sudo apt autoremove -y
	sudo snap refresh
	rustup update stable # update rust version
	cargo install-update -a
	flatpak update -y
	# go install github.com/tsenart/vegeta@latest
	# go install github.com/hashicorp/terraform@latest
	sudo npm update --location=global
	sudo n latest
	bob install nightly
	nvim --headless "+Lazy! sync" +qa
	set +x
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

# Merge back ${1} branch into ${2}
function merge_back() {
	[[ "${1}" = "" || "${2}" = "" ]] && echo -e "usage:\n\tmerge_back <from> <to>\nExample:\n\tmerge_back \$(git rev-parse --abbrev-ref HEAD) upstream/master" && return 1
	git fetch --all
	git stash
	CURRBR=$(git rev-parse --abbrev-ref HEAD)

	git checkout "${1}"
	git pull
	git checkout "${2}"
	git pull

	FROM="${1#*/}" # upstream/v2.9 -> v2.9
	TO="${2#*/}" # upstream/master -> master
	git branch -D "merge-current-${FROM}-into-${TO}"
	git checkout -b "merge-current-${FROM}-into-${TO}"
	git push -fu tom "merge-current-${FROM}-into-${TO}"

	git merge "${1}" -m "Merge current ${FROM} into ${TO}"
	if [ $? ]; then
		echo -e "It seems that you have merge errors to fix.\nOnce you resovled all of them, simply do this:"
		TO_ECHO="true"
	fi

	ARGS="--title 'Merge current ${FROM} into ${TO}'"
	ARGS+=" --body '<h3> What does this PR do?</h3><br/>Merge current ${FROM} branch into ${TO}.<br/><br/><h3>Motivation</h3><br/>Be synced.'"
	ARGS+=" --base ${2}"
	ARGS+=" --head merge-current-${FROM}-into-${TO}"
	if [[ "$(git remote -v)" = *"traefik/traefik"* ]]; then
		ARGS+=" --label status/2-needs-review --label bot/light-review --label bot/merge-method-ff"
		ARGS+=" --milestone ${TO}"
	fi

	if [ "${TO_ECHO}" == "true" ]; then
		echo -e "gh pr create ${ARGS}"
	else
		echo -e "${ARGS}" | xargs gh pr create
		git checkout "${CURRBR}"
	fi

	git stash apply
}

# vim:ft=bash noet
