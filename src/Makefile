# So that we build the correct versions of adaper, visa service,
# compiler and bas you should tag those repos and set TAG before 
# calling make.
ifeq ($(strip $(TAG)), )
    $(error Environment variable TAG must be set)
endif



BUILDDIR=build
BINDIR=$(BUILDDIR)/bin



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


# We only need ph
.PHONY: build-code
build-core:
	@mkdir -p $(BINDIR)
	@cd $(BUILDDIR)/zpr-core && git fetch && git checkout $(TAG) && git pull origin $(TAG)
	$(MAKE) -C $(BUILDDIR)/zpr-core/adapter/ph 
	@cp $(BUILDDIR)/zpr-core/adapter/ph/target/debug/ph $(BINDIR)


.PHONY: build-compiler
build-compiler:
	@mkdir -p $(BINDIR)
	@cd $(BUILDDIR)/zpr-compiler && git fetch && git checkout $(TAG) && git pull origin $(TAG)
	$(MAKE) -C $(BUILDDIR)/zpr-compiler
	@cp $(BUILDDIR)/zpr-compiler/target/debug/zplc $(BINDIR)
	@cp $(BUILDDIR)/zpr-compiler/target/debug/zpdump $(BINDIR)


.PHONY: build-visaservice
build-visaservice:
	@mkdir -p $(BINDIR)
	@cd $(BUILDDIR)/zpr-visaservice && git fetch && git checkout $(TAG) && git pull origin $(TAG)
	$(MAKE) -C $(BUILDDIR)/zpr-visaservice/core
	@cp $(BUILDDIR)/zpr-visaservice/core/build/vservice $(BINDIR)
	$(MAKE) -C $(BUILDDIR)/zpr-visaservice/vs-admin 
	@cp $(BUILDDIR)/zpr-visaservice/vs-admin/target/debug/vs-admin $(BINDIR)


.PHONY: build-bas
build-bas:
	mkdir -p $(BINDIR)
	@cd $(BUILDDIR)/zpr-bas && git fetch && git checkout $(TAG) && git pull origin $(TAG)
	$(MAKE) -C $(BUILDDIR)/zpr-bas
	@cp $(BUILDDIR)/zpr-bas/target/debug/bas $(BINDIR)


.PHONY: clean
clean:
	@rm -rf $(BUILDDIR)
