SHELL = /bin/bash

all: default

deps:
	@which -s brew || (echo "Please install brew"; exit 1)
	@which -s aws || brew install aws
	@which -s jq || brew install jq

## Start a clean shell
default:
	@env -i HOME="$$HOME" \
	        PATH="$$PATH" \
	        USER="$$USER" \
	        SHELL="$$SHELL" \
	        TERM="$$TERM" \
	        LS_COLORS="$$LS_COLORS" \
	        CLICOLOR="$$CLICOLOR" \
	        SSH_AUTH_SOCK="$$SSH_AUTH_SOCK" \
	          $(SHELL) --rcfile ./profile || true
