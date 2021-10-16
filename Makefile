all: test
	./install.sh

test:
	shellcheck -e SC2139,SC1091 bash_aliases
	shellcheck -e SC1090,SC2046 bash_functions
	shellcheck -e  SC1073,SC1072,SC1009 install.sh
	shellcheck -x -e SC2034,SC1090,SC1091 bashrc
	shellcheck demo/entrypoint.sh
	shfmt -l -d bash* *.sh **/*.sh


BIN = docker-compose -f demo/docker-compose.yml
demo-down:
	$(BIN) down

demo-build:
	$(BIN) build

demo-up:
	$(BIN) up

demo-run:
	$(BIN) run dotfiles bash

demo:demo-down
demo:demo-build
demo:demo-up
demo:demo-run
