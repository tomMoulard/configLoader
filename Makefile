all:
	./install.sh

BIN = docker-compose
test-down:
	$(BIN) down

test-build:
	$(BIN) build

test-up:
	$(BIN) up

test-run:
	$(BIN) run dotfiles bash

test:test-down
test:test-build
test:test-up
test:test-run
