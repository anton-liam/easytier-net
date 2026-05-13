SHELL := /bin/sh

TARGET ?= x86_64-linux

.PHONY: bootstrap vendor build lab-up lab-test lab-down clean status

bootstrap:
	./scripts/bootstrap.sh

vendor:
	./scripts/vendor-sync.sh

build:
	./scripts/build-target.sh "$(TARGET)"

lab-up:
	./tests/lab/scripts/lab-up.sh

lab-test:
	./tests/lab/scripts/lab-test.sh

lab-down:
	./tests/lab/scripts/lab-down.sh

status:
	git status --short

clean:
	rm -rf build dist

