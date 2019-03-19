#!/bin/bash

THIS_PWD="$PWD"

# installing YouCompleteMe
cd bundle/YouCompleteMe/
git submodule update --init --recursive
./install.py --all

cd "$THIS_PWD"
