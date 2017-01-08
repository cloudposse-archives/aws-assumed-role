SHELL = /bin/bash
OS := $(shell uname -s | tr '[:upper:]' '[:lower:]')

all: default

darwin:
	@which -s brew || (echo "Please install brew"; exit 1)
	@which -s aws || brew install aws
	@which -s jq || brew install jq

linux:
	@which pip || sudo apt-get -y install python-pip
	@which aws || sudo pip install awscli
	@which jq || sudo apt-get -y install jq

deps: $(OS)

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
