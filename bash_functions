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
        # display usage if no parameters given
        echo "Usage: extract <path/file_name>.<zip|rar|bz2|gz|tar|tbz2|tgz|Z|7z|xz|ex|tar.bz2|tar.gz|tar.xz>"
        echo "       extract <path/file_name_1.ext> [path/file_name_2.ext] [path/file_name_3.ext]"
        return 1
    else
        for n in $@
        do
            if [ -f "$n" ] ; then
                case "${n%,}" in # migth use file to detect file type
                    #file $n | awk '{print $2}'
                    *.tar.bz2|*.tar.gz|*.tar.xz|*.tbz2|*.tgz|*.txz|*.tar)
                    tar xvf "$n"       ;;
                *.lzma)      unlzma ./"$n"      ;;
                *.bz2)       bunzip2 ./"$n"     ;;
                *.rar)       unrar x -ad ./"$n" ;;
                *.gz)        gunzip ./"$n"      ;;
                *.zip)       unzip ./"$n"       ;;
                *.z)         uncompress ./"$n"  ;;
                *.7z|*.arj|*.cab|*.chm|*.deb|*.dmg|*.iso|*.lzh|*.msi|*.rpm|*.udf|*.wim|*.xar)
                    7z x ./"$n"        ;;
                *.xz)        unxz ./"$n"        ;;
                *.exe)       cabextract ./"$n"  ;;
                *)
                    echo "extract: '$n' - unknown archive method"
                    return 1
                    ;;
            esac
        else
            echo "'$n' - file does not exist"
            return 1
            fi
        done
    fi
}

# Generate a "password"
function genpwd { < /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-16};echo; }

# cd into a directory and list its contents
function cdl {
    cd "$@"
    ls
}

function _disown {
    bash -c "$1" >& /dev/null &
    disown $!
}

TMP=$(mktemp)

for fun in firefox chromium google-chrome thunderbird evince; do
    echo "function $fun { _disown \"$fun \$@\"; };" >> ${TMP}
done

source ${TMP} && rm ${TMP}

function dc {
    docker-compose $(find -name 'docker-compose*.yml' -type f -printf '%p\t%d\n'  2>/dev/null | sort -n -k2 | cut -f 1 | awk '{print "-f "$0}') $@
}

function upgrade {
    apt list --upgradable;
    for x in update upgrade; do
        sudo apt $x -y;
    done
    sudo apt autoremove -y;
    sudo snap refresh;
}

# Removes spaces from a file name
# file\ with \spaces.py -> file-with-spaces.py
function remove-spaces {
    FILE=$(echo $1 | sed 's/ /-/g')
    mv "$1" "$FILE"
    echo $FILE
}

# vim:ft=bash
