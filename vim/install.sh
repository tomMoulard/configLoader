#!/bin/bash

FILENAME="plugin_list.txt"

function splt() {
    IFS=" "
    read -ra ADDR <<< "$1"
    PLUGIN_NAME="${ADDR[0]}"
    PLUGIN_URL="${ADDR[1]}"
}

while read -r line; do
    splt "$line"
    printf "Installing %s(%s)\n" "$PLUGIN_NAME" "$PLUGIN_URL"
    git clone $PLUGIN_URL ./bundle/$PLUGIN_NAME >& /dev/null
    if [ $? -eq 128 ]; then
        cd ./bundle/$PLUGIN_NAME && git pull >& /dev/null && cd ../..
    fi
done < "$FILENAME"

