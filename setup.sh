#!/bin/bash

#saving the old config (just in case ...)
cat $HOME/.bashrc >> $HOME/.bashrc.old

if [ "$HOME/.bashrc" ]
then
    #put git:bashrc > .bashrc
    wget https://raw.githubusercontent.com/tomMoulard/configLoader/master/bashrc > $HOME/.bashrc
    echo "Bashrc imported!"
    #put git:alias > .aliases
    wget https://raw.githubusercontent.com/tomMoulard/configLoader/master/aliases >> $HOME/.bashrc
    echo "Aliases imported!"
    source $HOME/.bashrc
    echo Done!
elif [ "$HOME/.zshrc" ]
then
    echo zshrc
else
    echo not recognized
fi
