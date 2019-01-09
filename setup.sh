#!/bin/bash

# To use:
#  curl https://tom.moulard.org/setup/setup.sh | bash

BAS="https://raw.githubusercontent.com/tomMoulard/configLoader/master/"

ALI="${BAS}aliases"
BRC="${BAS}bashrc"
I3S="${BAS}i3/i3status.conf"
I3C="${BAS}i3/i3.conf"

replace_file() {
    # $1 is the filename
    # $2 is the url
    cat "$1" >> ${1}.old 2>/dev/null
    curl "$2" > "$1"
}

if [ "$HOME/.bashrc" ]
then
    # Put git:bashrc > .bashrc
    replace_file "$HOME/.bashrc" "$BRC"
    echo "Bashrc imported!"
    # Put git:alias > .aliases
    replace_file "$HOME/.bash_aliases" "$ALI"
    echo "Aliases imported!"
    . $HOME/.bashrc
    echo Done!
elif [ "$HOME/.zshrc" ]
then
    # TODO
    echo zshrc
else
    echo not recognized
fi

# i3
I3STATUS=0

for file in /proc/**/status; do
    if [ "$(cat "$file" | grep i3status)" != "" ]; then
        I3STATUS=1;
    fi
done

if [ $I3STATUS ];then
    echo "i3status is working"
    mkdir -p $HOME/.config/i3/
    mkdir -p $HOME/.config/i3status/
 
    replace_file "$HOME/.config/i3/config" "$I3C"
    replace_file "$HOME/.config/i3status/config" "$I3S"
fi
