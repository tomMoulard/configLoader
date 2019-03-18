#!/bin/bash

## How to
# git clone http://github.com/tommoulard/configLoader.git $HOME/.config

# createLink create a link between the file in the git repo and the output file
# $1 must be the file path
# $2 must be the output file path
function createLink() {
    if [ -L "$2" ]; then
        rm -r "$2"
    fi
    if [ -f "$2" ]; then
        mv "$2" "${2}.old"
    fi
    ln -s $PWD/${1} $2
}

# Xressourses
createLink Xresources "$HOME/.Xresources"
xrdb $HOME/.Xresources

# Font
createLink fonts "$HOME/.fonts"

# Vim
createLink vimrc "$HOME/.vimrc"
createLink vim "$HOME/.vim"
cd vim && ./install.sh && cd ..

# SSH
createLink ssh "$HOME/.ssh"

# Bash
createLink bashrc "$HOME/.bashrc"
createLink aliases "$HOME/.bash_aliases"
createLink bash_functions "$HOME/.bash_functions"

# Rxvt
createLink urxvt "$HOME/.urxvt"

# xinitrc
createLink xinitrc "$HOME/.xinitrc"

# config
mkdir -p $HOME/.config/
for FOLDER in config/*; do
    createLink $FOLDER "$HOME/.$FOLDER"
done
