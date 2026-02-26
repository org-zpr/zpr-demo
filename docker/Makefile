
IMAGENAME ?= ghcr.io/org-zpr/zpr-demo/zprdemo:latest

# Detect platform from binaries; default to amd64 if none are present.
DOCKER_PLATFORM := linux/amd64
ifneq ($(wildcard ../src/build/bin/*),)
  _BIN_INFO := $(shell file $(firstword $(wildcard ../src/build/bin/*)) 2>/dev/null)
  ifneq ($(findstring aarch64,$(_BIN_INFO))$(findstring arm64,$(_BIN_INFO)),)
    DOCKER_PLATFORM := linux/arm64
  endif
endif

.PHONY: info
info:
	@echo
	@echo "   sudo make build-image - build the docker image, pass IMAGENAME to override the tag"
	@echo "   sudo make up          - bring up the containers."
	@echo "   sudo make down        - bring down/clean up."
	@echo
	@echo "For a local build and run of the image, set IMAGENAAME to something."
	@echo "For example,"
	@echo
	@echo "IMAGENAME=zpr/demo:latest maake build-image"
	@echo

.PHONY: build-image
build-image:
	@cd .. && docker build -t $(IMAGENAME) -f docker/Dockerfile .

.PHONY: up
up:
	echo "IMAGE_NAME=$(IMAGENAME)" >.env
	echo "DOCKER_PLATFORM=$(DOCKER_PLATFORM)" >>.env
	docker compose down --volumes --remove-orphans
	docker network prune -f
	docker --debug compose up --build

.PHONY: down
down:
	echo "IMAGE_NAME=$(IMAGENAME)" >.env
	echo "DOCKER_PLATFORM=$(DOCKER_PLATFORM)" >>.env
	docker compose down

.PHONY: clean
clean:
	rm -rf .env
