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
function extract {
    if [ -z "$1" ]; then
        echo "Usage: ${FUNCNAME[0]} <path/file...>"
        return 1
    fi
    for n in "$@"; do
        if [ ! -f "${n}" ] ; then
            echo "${FUNCNAME[0]}: '${n}': file does not exist"
            continue
        fi
        FTYPE="$(file "${n%,}" | awk '{print $2}')"
        case "${FTYPE}" in
            "compress'd") uncompress ./"${n}"      ;; # compress -f <file*>
            7-zip)        7z x ./"${n}"            ;; # 7z a -t7z <archive.7z> <file*>
            Allegro)      pack u "${n}" "${n}.out" ;; # pack <files> <file out>
            LZMA)         unlzma ./"${n}"          ;; # lzma <file*>
            PE32)         cabextract ./"${n}"      ;;
            RAR)          unrar x -ad ./"${n}"     ;; # rar a -r <archive.rar> <file*>
            XZ)           unxz ./"${n}"            ;; # xz <file>
            Zip)          unzip ./"${n}"           ;; # zip <archive.zip> <file*>
            bzip2)        bunzip2 ./"${n}"         ;; # bzip2 <file*>
            gzip)         tar xvf "${n}"           ;; # tar cfz <archive.tar> <file*>
            *)
                echo "${FUNCNAME[0]}: '${n}': '${FTYPE}' is a unknown archive method"
                continue
                ;;
        esac
    done
}

# Generate a "password"
function genpwd { < /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c"${1:-16}";echo; }

function _disown {
    bash -c "$1" >& /dev/null &
    disown $!
}

TMP=$(mktemp)

for fun in firefox chromium google-chrome thunderbird evince; do
    echo "function ${fun} { _disown \"${fun} \$@\"; };" >> "${TMP}"
done

source "${TMP}" && rm "${TMP}"

function dc {
    docker-compose $(find . -name 'docker-compose*.yml' -type f -printf '%p\t%d\n' 2>/dev/null | sort -n -k2 | cut -f 1 | awk '{print "-f "$0}') "$@"
}

function upgrade {
    apt list --upgradable;
    for x in update upgrade; do
        sudo apt $x -y;
    done
    sudo apt autoremove -y;
    sudo snap refresh;
}

# Removes spaces from a file name (can use globing)
# file\ with \spaces.py -> file-with-spaces.py
# file\ - \stuff.py -> file-stuff.py
function remove-spaces {
    for INPUT in "$@"; do
        FILE="${INPUT// /-}"
        FILE="${FILE//+(-)/-}"
        mv "${INPUT}" "${FILE}"
        echo "${FILE}"
    done
}

# vim:ft=bash
