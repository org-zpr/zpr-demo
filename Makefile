VERSION ?= `date +%Y%m%d`

# ZPRSRCDIR - Where the ZPR sources are built.
ZPRSRCDIR=src

# RELEASEDIR - Where we collect all the files for this release.
RELEASEDIR=release

# CONFIGIDR - Where the credentials and bas are created/configured.
CONFIGDIR=config


# POLICY - What policy to compile
POLICY=demo-20250919.zpl
POLICYBIN = $(POLICY:.zpl=.bin)

# The config directory under release
RCONFDIR=$(RELEASEDIR)/conf



.PHONY: info
info:
	@echo 
	@echo "This makefile is for building a ZPR demo release. Access to all"
	@echo "the relevant ZPR repositories and build tools is required."
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
release: clean-release zprbins creds configs policy
	@echo "To build a new docker image cd to 'docker' dir and use Makefile there."


.PHONY: zprbins
zprbins:
	$(MAKE) -C $(ZPRSRCDIR) 

.PHONY: creds
creds:
	$(MAKE) -C $(CONFIGDIR) creds
	$(MAKE) -C $(CONFIGDIR) basdb

.PHONY: configs
configs:
	@mkdir -p $(RCONFDIR)
	@cp $(CONFIGDIR)/build/keys/* $(RCONFDIR)
	@cp $(CONFIGDIR)/build/authority/* $(RCONFDIR)
	@cp $(CONFIGDIR)/zprnet/* $(RCONFDIR)
	@rm -rf $(RELEASEDIR)/db
	@mv $(CONFIGDIR)/db $(RELEASEDIR)/


.PHONY: policy
policy:
	$(ZPRSRCDIR)/build/bin/zplc -k $(RCONFDIR)/zpr-rsa-key.pem $(RCONFDIR)/$(POLICY)
	@echo "copying policy binary to initial.bin for the docker..."
	cp $(RCONFDIR)/$(POLICYBIN) $(RCONFDIR)/initial.bin

# The release target will wipe the release/ dir.
.PHONY: clean-release
clean-release:
	rm -rf $(RELEASEDIR)
	@mkdir $(RELEASEDIR)
	@echo "$(VERSION)" >$(RELEASEDIR)/VERSION


.PHONY: clean
clean: clean-release
	$(MAKE) -C $(ZPRSRCDIR) clean
	$(MAKE) -C $(CONFIGDIR) clean


.DEFAULT_GOAL := info
