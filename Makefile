SHELL := /bin/sh

TARGET ?= x86_64-linux

.PHONY: bootstrap vendor build fetch-nanopi-r3s-sdk build-nanopi-r3s-docker lab-up lab-test lab-down utm-deploy-web utm-stability-test clean status

bootstrap:
	./scripts/bootstrap.sh

vendor:
	./scripts/vendor-sync.sh

build:
	./scripts/build-target.sh "$(TARGET)"

fetch-nanopi-r3s-sdk:
	./scripts/openwrt-fetch-sdk.sh

build-nanopi-r3s-docker:
	./scripts/openwrt-build-agent-in-docker.sh

lab-up:
	./tests/lab/scripts/lab-up.sh

lab-test:
	./tests/lab/scripts/lab-test.sh

lab-down:
	./tests/lab/scripts/lab-down.sh

utm-deploy-web:
	./scripts/utm-deploy-web.sh

utm-stability-test:
	./scripts/utm-stability-test.sh

status:
	git status --short

clean:
	rm -rf build dist
