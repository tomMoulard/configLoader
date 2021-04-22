#!/bin/bash

for x in bundle/*; do
	echo $x
	cd $x
	git pull origin master
	cd ../..
done

# if busy:
# git submodule foreach git pull origin master
