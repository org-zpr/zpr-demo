BINARIES=node vservice adapter zpc zpr-pki
CONFIG=config
SCRIPTS=scripts

all: build pki policy

build:
	@echo "Ensure all binaries are present in ./bin:"
	@for bin in $(BINARIES); do \
		if [ ! -f ./bin/$$bin ]; then echo "Missing ./bin/$$bin"; exit 1; fi \
	done

pki:
	@bash $(SCRIPTS)/gen_pki.sh

policy:
	./bin/zpc -k $(CONFIG)/authority/zpr-rsa-key.pem $(CONFIG)/policies/policy.zpl

up:
	docker compose up --build

down:
	docker compose down

reset: down pki policy up
