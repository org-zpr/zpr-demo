ZPLC ?= zplc
KEY := zpr-rsa-key.pem

OBJS := m4-demo-0818.bin

info:
	@echo
	@echo    Use \'make policy\' to recompile the m4 policy
	@echo
	@echo    Requires that the zplc binary is on your path,
	@echo    or set the ZPLC variable to point to it.
	@echo


policy: $(OBJS)


%.bin: %.zpl %.zplc
	$(ZPLC) -k $(KEY) $<


.PHONY: info policy

.DEFAULT_GOAL: info
