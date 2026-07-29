ZPR_ROOT ?=

.PHONY: all ph visaservice compiler check-zpr-root clean

all: ph visaservice compiler

check-zpr-root:
	@test -n "$(ZPR_ROOT)" || { \
		echo "ZPR_ROOT must point to the directory containing the ZPR repositories" >&2; \
		exit 1; \
	}
	@test -d "$(ZPR_ROOT)/zpr-core" || { \
		echo "ZPR_ROOT=$(ZPR_ROOT) does not contain zpr-core" >&2; \
		exit 1; \
	}

ph: check-zpr-root
	mkdir -p bin
	cd "$(ZPR_ROOT)/zpr-core/adapter/ph" && cargo build --release
	cp "$(ZPR_ROOT)/zpr-core/target/release/ph" bin/

visaservice: check-zpr-root
	mkdir -p bin
	cd "$(ZPR_ROOT)/zpr-visaservice" && cargo build --release
	cp "$(ZPR_ROOT)/zpr-visaservice/target/release/vs" \
		"$(ZPR_ROOT)/zpr-visaservice/target/release/vs-admin" \
		"$(ZPR_ROOT)/zpr-visaservice/target/release/vsapikey" bin/

compiler: check-zpr-root
	mkdir -p bin
	cd "$(ZPR_ROOT)/zpr-compiler" && cargo build --release
	cp "$(ZPR_ROOT)/zpr-compiler/target/release/zplc" \
		"$(ZPR_ROOT)/zpr-compiler/target/release/zpdump" bin/

clean:
	rm -rf bin
