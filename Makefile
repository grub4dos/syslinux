## -----------------------------------------------------------------------
##
##   Copyright 1998-2009 H. Peter Anvin - All Rights Reserved
##   Copyright 2009-2014 Intel Corporation; author: H. Peter Anvin
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
##   Boston MA 02111-1307, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

#
# Main Makefile for SYSLINUX
#

all_firmware := bios

#
# topdir is only set when we are doing a recursive make. Do a bunch of
# initialisation if it's unset since this is the first invocation.
#
ifeq ($(topdir),)

topdir = $(CURDIR)

#
# Because we need to build modules multiple times, e.g. for BIOS,
# efi32, efi64, we output all object and executable files to a
# separate object directory for each firmware.
#
# The output directory can be customised by setting the O=/obj/path/
# variable when invoking make. If no value is specified the default
# directory is the top-level of the Syslinux source.
#
ifeq ("$(origin O)", "command line")
	OBJDIR := $(O)
else
	OBJDIR = $(topdir)
endif

# If the output directory does not exist we bail because that is the
# least surprising thing to do.
cd-output := $(shell cd $(OBJDIR) && /bin/pwd)
$(if $(cd-output),, \
	$(error output directory "$(OBJDIR)" does not exist))

#
# These environment variables are exported to every invocation of
# make,
#
# 'topdir' - the top-level directory containing the Syslinux source
# 'objdir' - the top-level directory of output files for this firmware
# 'MAKEDIR' - contains Makefile fragments
# 'OBJDIR' - the top-level directory of output files
#
# There are also a handful of variables that are passed to each
# sub-make,
#
# SRC - source tree location of the module being compiled
# OBJ - output tree location of the module being compiled
#
# A couple of rules for writing Makefiles,
#
# - Do not use relative paths, use the above variables
# - You can write $(SRC) a lot less if you add it to VPATH
#

MAKEDIR = $(topdir)/mk
export MAKEDIR topdir OBJDIR

include $(MAKEDIR)/syslinux.mk
-include $(OBJDIR)/version.mk

private-targets = prerel unprerel official release burn isolinux.iso \
		  preupload upload test unittest regression spotless

ifeq ($(MAKECMDGOALS),)
	MAKECMDGOALS += all
endif

#
# The 'bios', 'efi32' and 'efi64' are dummy targets. Their only
# purpose is to instruct us which output directories need
# creating. Which means that we always need a *real* target, such as
# 'all', appended to the make goals.
#
real-target := $(filter-out $(all_firmware), $(MAKECMDGOALS))
real-firmware := $(filter $(all_firmware), $(MAKECMDGOALS))

ifeq ($(real-target),)
	real-target = all
endif

ifeq ($(real-firmware),)
	real-firmware = $(firmware)
endif

.PHONY: $(filter-out $(private-targets), $(MAKECMDGOALS))
$(filter-out $(private-targets), $(MAKECMDGOALS)):
	$(MAKE) -C $(OBJDIR) -f $(CURDIR)/Makefile SRC="$(topdir)" \
		OBJ=$(OBJDIR) objdir=$(OBJDIR) $(BUILDOPTS) \
		$(MAKECMDGOALS)

unittest:
	printf "Executing unit tests\n"
	$(MAKE) -C core/mem/tests all
	$(MAKE) -C com32/lib/syslinux/tests all

regression:
	$(MAKE) -C tests SRC="$(topdir)/tests" OBJ="$(topdir)/tests" \
		objdir=$(OBJDIR) $(BUILDOPTS) \
		-f $(topdir)/tests/Makefile all

test: unittest regression

# Hook to add private Makefile targets for the maintainer.
-include $(topdir)/Makefile.private

else # ifeq ($(topdir),)

include $(MAKEDIR)/syslinux.mk

# Hook to add private Makefile targets for the maintainer.
-include $(topdir)/Makefile.private

#
# The BTARGET refers to objects that are derived from ldlinux.asm; we
# like to keep those uniform for debugging reasons; however, distributors
# want to recompile the installers (ITARGET).
#
# BOBJECTS and IOBJECTS are the same thing, except used for
# installation, so they include objects that may be in subdirectories
# with their own Makefiles.  Finally, there is a list of those
# directories.
#


MODULES = memdisk/memdisk \
	com32/menu/*.c32 com32/modules/*.c32 com32/mboot/*.c32 \
	com32/hdt/*.c32 com32/rosh/*.c32 com32/gfxboot/*.c32 \
	com32/sysdump/*.c32 com32/lua/src/*.c32 com32/chain/*.c32 \
	com32/lib/*.c32 com32/libutil/*.c32 com32/gpllib/*.c32 \
	com32/elflink/ldlinux/*.c32 com32/cmenu/libmenu/*.c32

export FIRMWARE FWCLASS ARCH BITS

BTARGET  = version.gen version.h $(OBJDIR)/version.mk
BOBJECTS = $(BTARGET) \
	core/pxelinux.0 core/lpxelinux.0 \
	core/isolinux.bin core/isolinux-debug.bin \
	$(MODULES)

# BSUBDIRs build the on-target binary components.

BSUBDIRS = codepage com32 lzo core memdisk

.PHONY: subdirs $(BSUBDIRS) test

ifeq ($(FIRMWARE),)

firmware = $(all_firmware)

# If no firmware was specified the rest of MAKECMDGOALS applies to all
# firmware.
ifeq ($(filter $(firmware),$(MAKECMDGOALS)),)
all tidy clean dist: $(all_firmware)

else

# Don't do anything for the rest of MAKECMDGOALS at this level. It
# will be handled for each of $(firmware).
tidy clean dist:

endif

#
# You'd think that we'd be able to use the 'define' directive to
# abstract the code for invoking make(1) in the output directory, but
# by using 'define' we lose the ability to build in parallel.
#
.PHONY: $(firmware)
bios:
	@mkdir -p $(OBJ)/bios
	$(MAKE) -C $(OBJ)/bios -f $(SRC)/Makefile SRC="$(SRC)" \
		objdir=$(OBJ)/bios OBJ=$(OBJ)/bios \
		FIRMWARE=BIOS FWCLASS=BIOS \
		ARCH=i386 LDLINUX=ldlinux.c32 $(MAKECMDGOALS)

else # FIRMWARE

all: all-local subdirs

all-local: $(BTARGET)
	-ls -l $(BOBJECTS)
subdirs: $(BSUBDIRS)

$(sort $(BSUBDIRS)):
	@mkdir -p $@
	$(MAKE) -C $@ SRC="$(SRC)/$@" OBJ="$(OBJ)/$@" \
		-f $(SRC)/$@/Makefile $(MAKECMDGOALS)

$(BINFILES):
	@mkdir -p $@
	$(MAKE) -C $@ SRC="$(SRC)/$@" OBJ="$(OBJ)/$@" \
		-f $(SRC)/$@/Makefile $(MAKECMDGOALS)

#
# List the dependencies to help out parallel builds.
core: com32

version.gen: $(topdir)/version $(topdir)/version.pl
	$(PERL) $(topdir)/version.pl $< $@ '%define < @'
version.h: $(topdir)/version $(topdir)/version.pl
	$(PERL) $(topdir)/version.pl $< $@ '#define < @'

local-tidy:
	rm -f *.o *.elf *_bin.c stupid.* patch.offset
	rm -f *.lsr *.lst *.map *.sec *.tmp
	rm -f $(OBSOLETE)

tidy: local-tidy $(BESUBDIRS) $(IESUBDIRS) $(BSUBDIRS) $(ISUBDIRS)

local-clean:
	rm -f $(ITARGET)

clean: local-tidy local-clean $(BESUBDIRS) $(IESUBDIRS) $(BSUBDIRS) $(ISUBDIRS)

local-dist:
	find . \( -name '*~' -o -name '#*' -o -name core \
		-o -name '.*.d' -o -name .depend \) -type f -print0 \
	| xargs -0rt rm -f

dist: local-dist local-tidy $(BESUBDIRS) $(IESUBDIRS) $(BSUBDIRS) $(ISUBDIRS)

# Shortcut to build linux/syslinux using klibc
klibc:
	$(MAKE) clean
	$(MAKE) CC=klcc ITARGET= ISUBDIRS='linux extlinux' BSUBDIRS=
endif # ifeq ($(FIRMWARE),)

endif # ifeq ($(topdir),)

local-spotless:
	find . \( -name '*~' -o -name '#*' -o -name core \
		-o -name '.*.d' -o -name .depend -o -name '*.so.*' \) \
		-type f -print0 \
	| xargs -0rt rm -f

spotless: local-spotless
	rm -rf $(all_firmware)

#
# Common rules that are needed by every invocation of make.
#
$(OBJDIR)/version.mk: $(topdir)/version $(topdir)/version.pl
	$(PERL) $(topdir)/version.pl $< $@ '< := @'
