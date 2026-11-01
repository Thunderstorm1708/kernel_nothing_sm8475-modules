# SPDX-License-Identifier: GPL-2.0
#
# LineageOS inline build of the Nothing Phone (2) vendor modules.
#
# BoardConfig:
#   TARGET_KERNEL_EXT_MODULE_ROOT := kernel/nothing/sm8475-modules
#   TARGET_KERNEL_EXT_MODULES := build
#
# Lineage runs this Makefile twice after building the kernel and its in-tree
# modules: once with no target (build) and once with modules_install. It builds
#   1. the Qualcomm SoC drivers (soc-repo, Kbuild generated from modules.bzl)
#   2. every techpack module of qcom/opensource (Kbuild generated from the
#      techpacks' Bazel files by gen_kbuild.py)
# and on install keeps, of the in-tree modules, only the GKI ones, which is the
# module set a kleaf build of this kernel ships.
#
# The device sets DEPMOD=true in TARGET_KERNEL_ADDITIONAL_FLAGS: the in-tree
# modules_install runs before this one can prune, and Lineage runs depmod itself.

BUILD_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
REPO_DIR := $(patsubst %/,%,$(dir $(BUILD_DIR)))

SOC_TARGET_VARIANT ?= waipio_perf
KBUILD_OUT := $(abspath $(if $(OUT_DIR),$(OUT_DIR),$(O)))
SOC_STAGING := $(KBUILD_OUT)/soc-repo-staging
TECHPACKS := $(KBUILD_OUT)/qcom-opensource

RSYNC ?= rsync

# M of soc-repo/build, the way Lineage gives it (relative to KERNEL_SRC)
SOC_M := $(patsubst %/build,%,$(M))/soc-repo/build

KERNEL_RELEASE = $(shell cat $(KBUILD_OUT)/include/config/kernel.release)

.PHONY: all soc techpacks modules_install clean

all: soc techpacks

soc:
	$(MAKE) -C $(REPO_DIR)/soc-repo/build M=$(SOC_M) SOC_TARGET_VARIANT=$(SOC_TARGET_VARIANT)

techpacks: soc
	mkdir -p $(TECHPACKS)/build/kbuild
	$(RSYNC) -a --exclude='.git/' $(REPO_DIR)/qcom/opensource/ $(TECHPACKS)/
	$(RSYNC) -a --delete $(BUILD_DIR)/kbuild/ $(TECHPACKS)/build/kbuild/
	KERNEL_SRC=$(KERNEL_SRC) sh $(TECHPACKS)/build/kbuild/genrules.sh $(TECHPACKS)/build/genrules
	{ echo 'LINUXINCLUDE := -I$(SOC_STAGING) -I$(SOC_STAGING)/arch/arm64/include' \
		'-I$(SOC_STAGING)/include -I$(SOC_STAGING)/include/uapi -I$(SOC_STAGING)/include/linux' \
		'$$(LINUXINCLUDE) -I$$(srctree)/'; \
	  cat $(BUILD_DIR)/kbuild/Kbuild; } > $(TECHPACKS)/Kbuild
	$(MAKE) -C $(KERNEL_SRC) M=$(TECHPACKS) modules \
		KBUILD_EXTRA_SYMBOLS=$(SOC_STAGING)/Module.symvers

modules_install:
	# Of the in-tree modules keep the GKI ones: the SoC config enables more
	# in-tree drivers than GKI ships, soc-repo builds its own copies of them,
	# and some of them depend on each other in a cycle depmod refuses.
	cd $(INSTALL_MOD_PATH)/lib/modules/$(KERNEL_RELEASE)/kernel && \
		find . -name '*.ko' | sed 's|^\./||' | sort > $(KBUILD_OUT)/in-tree-modules.txt && \
		comm -23 $(KBUILD_OUT)/in-tree-modules.txt $(BUILD_DIR)/gki_modules.txt | xargs -r rm -f
	# Like a kleaf build, sign only the GKI modules: the kernel configuration
	# signs on modules_install for them, the vendor modules stay unsigned
	$(MAKE) -C $(REPO_DIR)/soc-repo/build M=$(SOC_M) SOC_TARGET_VARIANT=$(SOC_TARGET_VARIANT) \
		CONFIG_MODULE_SIG_ALL= modules_install
	$(MAKE) INSTALL_MOD_STRIP=1 -C $(KERNEL_SRC) M=$(TECHPACKS) CONFIG_MODULE_SIG_ALL= modules_install

clean:
	$(MAKE) -C $(REPO_DIR)/soc-repo/build M=$(SOC_M) clean
	rm -rf $(TECHPACKS)
