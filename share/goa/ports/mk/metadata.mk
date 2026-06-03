#
# \brief  Print port meta data
# \author Christian Helmuth
# \date   2026-06-02
#

default: info

include $(PORTS_TOOL_DIR)/mk/common.inc
include $(PORT)

.NOTPARALLEL:

#
# Assertion for the presence of a LICENSE and VERSION declarations in the port
# description
#
ifeq ($(LICENSE),)
default: license_undefined
license_undefined:
	@$(ECHO) "Error: License undefined"; false
endif

ifeq ($(VERSION),)
default: version_undefined
version_undefined:
	@$(ECHO) "Error: Version undefined"; false
endif

info:
	@$(ECHO) "PORT:     $(PORT_NAME)"
	@$(ECHO) "LICENSE:  $(LICENSE)"
	@$(ECHO) "VERSION:  $(VERSION)"

%.file:
	@$(ECHO) "SOURCE:   $(URL($*))$(if $(VERSION($*)), VERSION $(VERSION($*)),) ($*)"

%.archive:
	@$(ECHO) "SOURCE:   $(URL($*))$(if $(VERSION($*)), VERSION $(VERSION($*)),) ($*)"

%.git:
	@$(ECHO) "SOURCE:   $(URL($*)) git $(REV($*)) ($*)"

%.svn:
	@$(ECHO) "SOURCE:   $(URL($*)) svn $(REV($*)) ($*)"

$(DOWNLOADS): info

default: $(DOWNLOADS)
