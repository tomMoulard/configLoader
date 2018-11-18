#!/bin/bash

#To use:
# curl https://tom.moulard.org/setup/setup.sh | bash

#saving the old config (just in case ...)
cat $HOME/.bashrc >> $HOME/.bashrc.old

if [ "$HOME/.bashrc" ]
then
    #put git:bashrc > .bashrc
    curl https://raw.githubusercontent.com/tomMoulard/configLoader/master/bashrc > $HOME/.bashrc
    echo "Bashrc imported!"
    #put git:alias > .aliases
    curl https://raw.githubusercontent.com/tomMoulard/configLoader/master/aliases >> $HOME/.bash_aliases
    echo "Aliases imported!"
    . $HOME/.bashrc
    echo Done!
elif [ "$HOME/.zshrc" ]
then
    echo zshrc
else
    echo not recognized
fi
