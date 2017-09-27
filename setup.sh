#!/bin/bash

if [ "$HOME/.bashrc" ]
then
    #put git:bashrc > .bashrc
    wget https://raw.githubusercontent.com/tomMoulard/configLoader/master/bashrc > $HOME/.bashrc
    source $HOME/.bashrc
    #put git:alias > .aliases
    wget https://raw.githubusercontent.com/tomMoulard/configLoader/master/aliases > $HOME/.aliases

    echo Done!
elif [ "$HOME/.zshrc" ]
then
    echo zshrc
else
    echo not recognized
fi