# So that we build the correct versions of adaper, visa service,
# compiler and bas you should tag those repos and set TAG before 
# calling make.
ifeq ($(strip $(TAG)), )
    $(error Environment variable TAG must be set)
endif



BUILDDIR=build
BINDIR=$(BUILDDIR)/bin

USE_DOCKER ?= 0
TOOLS_DIR  ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../tools)

# Note that the "build-in-docker" script actually runs `cargo build` not make.
ifeq ($(USE_DOCKER),1)
    MAKE_IN = $(TOOLS_DIR)/build-in-docker.sh
else
    MAKE_IN = $(MAKE) -C
endif



.PHONY: all
all: pull build


.PHONY: pull
pull:
	mkdir -p $(BUILDDIR)
	@if [ -d "$(BUILDDIR)/zpr-core/.git" ]; then \
		echo "zpr-core already pulled"; \
	else \
		git clone git@github.com:org-zpr/zpr-core.git $(BUILDDIR)/zpr-core; \
	fi
	@if [ -d "$(BUILDDIR)/zpr-compiler/.git" ]; then \
		echo "zpr-compiler already pulled"; \
	else \
		git clone git@github.com:org-zpr/zpr-compiler.git $(BUILDDIR)/zpr-compiler; \
	fi
	@if [ -d "$(BUILDDIR)/zpr-visaservice/.git" ]; then \
		echo "zpr-visaservice already pulled"; \
	else \
		git clone git@github.com:org-zpr/zpr-visaservice.git $(BUILDDIR)/zpr-visaservice; \
	fi
	@if [ -d "$(BUILDDIR)/zpr-bas/.git" ]; then \
		echo "zpr-bas already pulled"; \
	else \
		git clone git@github.com:org-zpr/zpr-bas.git $(BUILDDIR)/zpr-bas; \
	fi


.PHONY: build
build: build-core build-compiler build-visaservice build-bas


# Grab ph and ph-cli
.PHONY: build-core
build-core:
	@mkdir -p $(BINDIR)
	@cd $(BUILDDIR)/zpr-core && git fetch && git checkout $(TAG) && git pull origin $(TAG)
	$(MAKE_IN) $(BUILDDIR)/zpr-core
	@cp $(BUILDDIR)/zpr-core/target/debug/ph $(BINDIR)
	@cp $(BUILDDIR)/zpr-core/target/debug/ph-cli $(BINDIR)


.PHONY: build-compiler
build-compiler:
	@mkdir -p $(BINDIR)
	@cd $(BUILDDIR)/zpr-compiler && git fetch && git checkout $(TAG) && git pull origin $(TAG)
	$(MAKE_IN) $(BUILDDIR)/zpr-compiler
	@cp $(BUILDDIR)/zpr-compiler/target/debug/zplc $(BINDIR)
	@cp $(BUILDDIR)/zpr-compiler/target/debug/zpdump $(BINDIR)


.PHONY: build-visaservice
build-visaservice:
	@mkdir -p $(BINDIR)
	@cd $(BUILDDIR)/zpr-visaservice && git fetch && git checkout $(TAG) && git pull origin $(TAG)
	$(MAKE_IN) $(BUILDDIR)/zpr-visaservice
	@cp $(BUILDDIR)/zpr-visaservice/target/debug/vs $(BINDIR)
	@cp $(BUILDDIR)/zpr-visaservice/target/debug/vs-admin $(BINDIR)
	@cp $(BUILDDIR)/zpr-visaservice/target/debug/zpt $(BINDIR)

.PHONY: build-bas
build-bas:
	mkdir -p $(BINDIR)
	@cd $(BUILDDIR)/zpr-bas && git fetch && git checkout $(TAG) && git pull origin $(TAG)
	$(MAKE_IN) $(BUILDDIR)/zpr-bas
	@cp $(BUILDDIR)/zpr-bas/target/debug/bas $(BINDIR)


.PHONY: clean
clean:
	@rm -rf $(BUILDDIR)
