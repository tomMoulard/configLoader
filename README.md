# ConfigLoader
[![Codacy Badge](https://api.codacy.com/project/badge/Grade/27010672c81b484ebc88abe992f9fe40)](https://www.codacy.com/app/tomMoulard/configLoader?utm_source=github.com&amp;utm_medium=referral&amp;utm_content=tomMoulard/configLoader&amp;utm_campaign=Badge_Grade)
[![Build Status](https://travis-ci.com/tomMoulard/configLoader.svg?branch=master)](https://travis-ci.com/tomMoulard/configLoader)

Shell script to load my settings/dotfiles

## Usage

via https:
```bash
$ git clone --recurse-submodules https://github.com/tomMoulard/configLoader.git $HOME/workspace/configLoader/
$ cd $HOME/workspace/configLoader && make
```

Or via ssh
```bash
$ git clone --recurse-submodules git@github.com:tomMoulard/configLoader.git $HOME/workspace/configLoader/
$ cd $HOME/workspace/configLoader && make
```

Feel free the change configurations with your own taste.

Some environment variables are defined in the `.env` file.
You can use `cp .env.default .env` to populate your file, or `./install -c`.

## Options
When using the `install.sh` script, you can use options to help you during installation:
```
Usage ./install.sh
Option:
	-c,--config	Promt user to enter configuration variables
	-d,--debug	Activate debug mode
	-h,--help	Show this help
	-v,--verbose	Activate verbose mode
```

## Demo
If you want to try those configuration, there is a `demo` recipe in the `Makefile`.
When you do `make demo`, you will be creating a docker image with the configuration installed and ready to use it.

## Here are a few dependencies for you to fetch
(alphabetical sort)

```
arandr
autoconf
compton
curl
dunst
exa
feh
fzf
g++
gcc
gdebi
git
htop
imagemagick
make
numlockx
pavucontrol
rofi
rxvt-unicode
screenkey
scrot
speedtest-cli
tree
vim
wget
xdotool
zoxide
```

And here are some "fun" packages to have:
```
cava
cmatrix
toilet
```

## GTK themes:
```
gtk-chtheme
lxappearance
```
