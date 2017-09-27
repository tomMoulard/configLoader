#!/bin/bash

if [ "$HOME/.bashrc" ]
then
    echo bashrc
elif [ "$HOME/.zshrc" ]
then
    echo zshrc
else
    echo not recognized
fi