BUILDDIR=build
ZPRBUILDDIR=../src/build
BASDB=db


BAS=$(ZPRBUILDDIR)/bin/bas


.PHONY: info
info:
	@echo
	@echo "  make creds - rebuild the entire credential set for the demo"
	@echo "  make basdb - create the bas db entries and the bas keys"
	@echo "  make clean - wipe the creds build and bas directories"
	@echo


.PHONY: creds
creds:
	python3 ./tools/generate_artifacts.py --builddir $(BUILDDIR) --zprbuilddir $(ZPRBUILDDIR)


.PHONY: basdb
basdb:
	rm -rf $(BASDB)
	$(BAS) create admin.zpr.org
	$(BAS) add-attribute admin.zpr.org bas_id:1000
	$(BAS) add-attribute admin.zpr.org color:blue
	$(BAS) create cli.zpr.org
	$(BAS) add-attribute cli.zpr.org bas_id:1001
	$(BAS) add-attribute cli.zpr.org color:green
	$(BAS) create web.zpr.org
	$(BAS) add-attribute web.zpr.org bas_id:1234
	$(BAS) add-attribute web.zpr.org color:purple
	$(BAS) add-attribute web.zpr.org content:green
	@mkdir -p $(BUILDDIR)/keys
	cp $(BASDB)/cn.admin.zpr.org/private.pem $(BUILDDIR)/keys/adapter-admin-bas.key
	cp $(BASDB)/cn.cli.zpr.org/private.pem $(BUILDDIR)/keys/adapter-cli-bas.key
	cp $(BASDB)/cn.web.zpr.org/private.pem $(BUILDDIR)/keys/adapter-web-bas.key


.PHONY: clean
clean:
	rm -rf $(BUILDDIR)
	rm -rf $(BASDB)


.DEFAULT_GOAL := info

