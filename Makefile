BINARIES=node vservice adapter zpc zpr-pki
CONFIG=config
SCRIPTS=scripts

all: pull build pki

pull:
	@if [ -d "zpr-core/.git" ]; then \
		echo "zpr-core already pulled"; \
	else \
		git clone git@github.com:org-zpr/zpr-core.git; \
	fi
	@if [ -d "zpr-compiler/.git" ]; then \
		echo "zpr-compiler already pulled"; \
	else \
		git clone git@github.com:org-zpr/zpr-compiler.git; \
	fi
	@if [ -d "zpr-visaservice/.git" ]; then \
		echo "zpr-visaservice already pulled"; \
	else \
		git clone git@github.com:org-zpr/zpr-visaservice.git; \
	fi
	@if [ -d "zpr-bas/.git" ]; then \
		echo "zpr-bas already pulled"; \
	else \
		git clone git@github.com:org-zpr/zpr-bas.git; \
	fi


build: build-core build-compiler build-visaservice build-bas

build-core:
	@cd zpr-core && make it-gone && make it-so

build-compiler:
	@cd zpr-compiler && make clean && make build

build-visaservice:
	@cd zpr-visaservice && make clean && make build

build-bas:
	@cd zpr-bas && make clean && make build

build-image:
	@mkdir -p bin
	@cp zpr-core/adapter/ph/target/debug/ph bin
	@cp zpr-bas/target/debug/bas bin
	@cp zpr-compiler/target/debug/zplc bin
	@cp zpr-visaservice/core/build/vservice bin
	@docker build -t alohagarage/zpr:m4 .

docker-image: pull build build-image

pki:
	@python3 scripts/gen_pki.py

policy:
	./bin/zplc -k $(CONFIG)/authority/zpr-rsa-key.pem $(CONFIG)/policies/policy.zpl

up:
	docker compose down --volumes --remove-orphans; docker network prune -f; docker --debug compose up --build

clean:
	@rm -rf zpr-{core,compiler,visaservice}

down:
	docker compose down

reset: down pki policy up
