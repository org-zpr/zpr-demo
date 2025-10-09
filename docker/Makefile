ZPR_IMAGE_VERSION ?= $(USER)_$(shell date +%Y%m%d)
IMAGE_BASE_NAME=org.zpr/zprdemo

IMAGENAME=$(IMAGE_BASE_NAME):$(ZPR_IMAGE_VERSION)

.PHONY: info
info:
	@echo
	@echo "   sudo make build-image - build the docker image, pass ZPR_IMAGE_VERSION to set the tag"
	@echo "   sudo make up          - bring up the containers."
	@echo "   sudo make down        - bring down/clean up."
	@echo

.PHONY: build-image
build-image:
	@cd .. && docker build -t $(IMAGENAME) -f docker/Dockerfile .

.PHONY: up
up:
	echo "IMAGE_NAME=$(IMAGENAME)" >.env
	docker compose down --volumes --remove-orphans
	docker network prune -f
	docker --debug compose up --build

.PHONY: down
down:
	echo "IMAGE_NAME=$(IMAGENAME)" >.env
	docker compose down

.PHONY: clean
clean:
	rm -rf .env
