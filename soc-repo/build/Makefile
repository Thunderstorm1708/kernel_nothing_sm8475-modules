# SPDX-License-Identifier: GPL-2.0

M ?= $(shell pwd)

# This file is read twice: as the wrapper (make -C soc-repo/build) and as the
# Kbuild file of M (from the kernel's objtree). M and KCONFIG_EXT_PREFIX may be
# relative to KERNEL_SRC (LineageOS passes them that way), so resolve every path
# from the location of this file instead of from the current directory.
SOC_BUILD_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
EXT_ROOT := $(patsubst %/,%,$(dir $(SOC_BUILD_DIR)))

# Stage into the kernel out dir when there is one, keeping the source tree clean
ifneq ($(OUT_DIR),)
SOC_STAGING := $(abspath $(OUT_DIR))/soc-repo-staging
endif

DTSTREE ?= $(shell realpath -s \
	$(EXT_ROOT)/arch/arm64/boot/dts/vendor \
	--relative-to $(KERNEL_SRC))

srctree = $(KERNEL_SRC)
# -------------------------------------------------
# Common upstream source staging (macros only)
# -------------------------------------------------
include $(SOC_BUILD_DIR)/common_sources.mk
STAGING_DIR := $(shell realpath -s $(abspath $(SOC_STAGING)) --relative-to $(SOC_BUILD_DIR))

soc = $(abspath $(SOC_STAGING))
LINUXINCLUDE := \
  -I$(soc)/. \
  -I$(soc)/arch/arm64/include \
  -I$(soc)/include \
  -I$(soc)/include/uapi \
  -I$(soc)/include/linux \
  $(LINUXINCLUDE) \
  -I$(srctree)/

# -------------------------------------------------
# Module list
# -------------------------------------------------
# With SOC_TARGET_VARIANT set (e.g. waipio_perf), build exactly the modules the
# Bazel registry (modules.bzl) enables for it: Kbuild.<variant> is generated
# from the registry by gen_kbuild.py and becomes the Kbuild of the staging dir.
# Without it, descend into the per-directory Makefiles of the tree.
SOC_KBUILD := $(if $(SOC_TARGET_VARIANT),$(SOC_BUILD_DIR)/Kbuild.$(SOC_TARGET_VARIANT))

obj-y += $(STAGING_DIR)/arch/arm64/gunyah/
obj-y += $(STAGING_DIR)/drivers/
obj-y += $(STAGING_DIR)/kernel/
obj-y += $(STAGING_DIR)/lib/
obj-y += $(STAGING_DIR)/mm/
obj-y += $(STAGING_DIR)/net/
obj-y += $(STAGING_DIR)/sound/

# -------------------------------------------------
# Targets
# -------------------------------------------------
ifneq ($(SOC_KBUILD),)
# The staging dir is the kbuild M, given as an absolute path
KBUILD_M := $(soc)
else
# Since Linux 6.11 a relative M is resolved against the objtree, while LineageOS
# passes M relative to KERNEL_SRC. Mirror this directory to where kbuild will
# look for it, so the objects also land in the out dir, next to the staging.
KBUILD_M := $(M)
ifeq ($(filter /%,$(M)),)
KBUILD_M_DIR := $(abspath $(if $(O),$(O),$(KERNEL_SRC))/$(M))
endif
endif

all:
	$(STAGE_COMMON_SOURCES)
ifneq ($(SOC_KBUILD),)
	{ echo 'LINUXINCLUDE := -I$$(src) -I$$(src)/arch/arm64/include -I$$(src)/include' \
		'-I$$(src)/include/uapi -I$$(src)/include/linux $$(LINUXINCLUDE) -I$$(srctree)/'; \
	  cat $(SOC_KBUILD); } > $(soc)/Kbuild
else ifneq ($(KBUILD_M_DIR),)
	$(MKDIR_P) $(KBUILD_M_DIR)
	$(RSYNC) -a $(SOC_BUILD_DIR)/ $(KBUILD_M_DIR)/
endif
	$(MAKE) -C $(KERNEL_SRC) M=$(KBUILD_M) modules $(KBUILD_OPTIONS)
ifneq ($(wildcard $(EXT_ROOT)/arch/arm64/boot/dts/vendor/Makefile),)
	$(MAKE) -C $(KERNEL_SRC) dtbs V=1 dtstree=$(DTSTREE)
endif

modules_install:
	$(MAKE) INSTALL_MOD_STRIP=1 -C $(KERNEL_SRC) M=$(KBUILD_M) modules_install

clean:
	$(MAKE) -C $(KERNEL_SRC) M=$(KBUILD_M) clean
