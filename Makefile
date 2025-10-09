VERSION ?= `date +%Y%m%d`

# ZPRSRCDIR - Where the ZPR sources are built.
ZPRSRCDIR=src

# ZPRBINDIR - Where the ZPR binaries end up after build.
ZPRBINDIR=$(ZPRSRCDIR)/build/bin

# RELEASEDIR - Where we collect all the files for this release.
RELEASEDIR=release

# Temporary build files (including artifact tgz)
BUILDDIR=build

# CONFIGIDR - Where the credentials and bas are created/configured.
CONFIGDIR=config

# POLICY - What policy to compile
POLICY=demo.zpl
POLICYBIN = $(POLICY:.zpl=.bin)

# RCONFDIR - The config directory under release
RCONFDIR=$(RELEASEDIR)/conf

# ZPRARTIFACTS - Where we put the binaries to distributed with the docker.
# This gets tar'd up.
ZPRARTIFACTS=zpr-$(VERSION)

# RBINDIR - The artifacts directory under build 
RBINDIR=$(BUILDDIR)/$(ZPRARTIFACTS)


ARCH := $(shell uname -m)
RELEASE_TGZ := "release-$(VERSION)-linux-$(ARCH).tar.gz"


.PHONY: info
info:
	@echo 
	@echo "This makefile is for building a ZPR demo release. Access to all"
	@echo "the relevant ZPR repositories and build tools is required."
	@echo
	@echo "For zprbins and release you must set TAG variable to the TAG"
	@echo "that should be checked out from the various source repos."
	@echo
	@echo "make options:"
	@echo "  make release - create a new zpr demo release"
	@echo
	@echo "  make zprbins - pull and build the zpr tools required"
	@echo "  make creds   - create credentials for the demo network"
	@echo "  make configs - move all the config material into the release directory"
	@echo "  make policy  - compile the policy in release directory"
	@echo


.PHONY: release
release: clean-release zprbins creds configs policy artifacts
	@echo "To build a new docker image cd to 'docker' dir and use Makefile there."


.PHONY: zprbins
zprbins:
	$(MAKE) -C $(ZPRSRCDIR) 


.PHONY: creds
creds:
	$(MAKE) -C $(CONFIGDIR) creds
	$(MAKE) -C $(CONFIGDIR) basdb
	@mkdir -p $(RELEASEDIR)
	@rm -rf $(RELEASEDIR)/db
	@mv $(CONFIGDIR)/db $(RELEASEDIR)/


.PHONY: configs
configs:
	@mkdir -p $(RCONFDIR)
	@cp $(CONFIGDIR)/build/keys/* $(RCONFDIR)
	@cp $(CONFIGDIR)/build/authority/* $(RCONFDIR)
	@cp $(CONFIGDIR)/zprnet/* $(RCONFDIR)


.PHONY: policy
policy:
	$(ZPRSRCDIR)/build/bin/zplc -k $(RCONFDIR)/zpr-rsa-key.pem $(RCONFDIR)/$(POLICY)
	@echo "copying policy binary to initial.bin for the docker..."
	cp $(RCONFDIR)/$(POLICYBIN) $(RCONFDIR)/initial.bin


.PHONY: artifacts
artifacts:
	@mkdir -p $(RBINDIR)
	@cp $(ZPRBINDIR)/ph $(RBINDIR)
	@cp $(ZPRBINDIR)/vs-admin $(RBINDIR)
	@cp $(ZPRBINDIR)/zpdump $(RBINDIR)
	@cp $(ZPRBINDIR)/zplc $(RBINDIR)
	@cd $(BUILDDIR) && tar zcvf $(RELEASE_TGZ) $(ZPRARTIFACTS)
	@echo "Created artifact bundle in $(BUILDDIR)/$(RELEASE_TGZ)"


# The release target will wipe the release/ dir.
.PHONY: clean-release
clean-release:
	rm -rf $(RELEASEDIR)
	@mkdir $(RELEASEDIR)
	@echo "$(VERSION)" >$(RELEASEDIR)/VERSION


.PHONY: clean
clean: clean-release
	@rm -rf $(BUILDDIR)
	$(MAKE) TAG=foo -C $(ZPRSRCDIR) clean
	$(MAKE) -C $(CONFIGDIR) clean


.DEFAULT_GOAL := info
