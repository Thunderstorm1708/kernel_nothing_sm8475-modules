#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# Build the Nothing Phone (2) kernel exactly the way a LineageOS 24.0 ROM build
# does (vendor/lineage config/BoardConfigKernel.mk + build/tasks/kernel.mk):
# same toolchain prebuilts, same make invocations and flags, same order, the
# same per-partition module packaging and depmod checks. Only the parts of the
# Android build system around it are left out.
#
# Run from the top of a tree laid out like a ROM tree (the CI workflow sets one
# up): device/nothing/Pong, kernel/nothing/sm8475{,-modules,-devicetrees},
# vendor/lineage, build/soong/rust/config/global.go and the prebuilts.
#
# Outputs, where the ROM build puts them:
#   out/target/product/Pong/kernel, dtb.img, dtbo.img
#   out/target/product/Pong/{vendor_dlkm,vendor_ramdisk,recovery/root}/lib/modules
set -eo pipefail
shopt -s nullglob

T=$(pwd)
DEVICE_PATH=${DEVICE_PATH:-device/nothing/Pong}
PRODUCT_OUT=out/target/product/${TARGET_DEVICE:-Pong}
OBJ=$PRODUCT_OUT/obj
HOST_OUT_EXECUTABLES=out/host/linux-x86/bin
step() { echo; echo "==== $* ($(date -u +%H:%M:%S))"; }

# ---------------------------------------------------------------------------
# Board variables, evaluated from the device's BoardConfig.mk by make
BC=$(mktemp -d)
sed -e '/^[[:space:]]*-\?include /d' "$DEVICE_PATH/BoardConfig.mk" > "$BC/BoardConfig.mk"
VARS="TARGET_KERNEL_SOURCE TARGET_KERNEL_CONFIG TARGET_KERNEL_CONFIG_EXT TARGET_KERNEL_KCONFIG_EXT_PREFIX
 TARGET_KERNEL_ADDITIONAL_FLAGS TARGET_KERNEL_LIBC_SYSROOT_USE TARGET_KERNEL_MIXED_MODE
 TARGET_KERNEL_EXT_MODULE_ROOT TARGET_KERNEL_EXT_MODULES TARGET_KERNEL_CLANG_VERSION
 TARGET_KERNEL_RUST_VERSION TARGET_KERNEL_CLANG_AUTOFDO_PROFILE TARGET_KERNEL_DTB KERNEL_LTO
 BOARD_KERNEL_IMAGE_NAME BOARD_KERNEL_PAGESIZE BOARD_KERNEL_SEPARATED_DTBO BOARD_DTBO_CFG
 BOARD_INCLUDE_DTB_IN_BOOTIMG TARGET_DTB_LIST_WILDCARD BOARD_USES_VENDOR_DLKMIMAGE
 BOARD_VENDOR_KERNEL_MODULES_LOAD BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD
 BOARD_RECOVERY_RAMDISK_KERNEL_MODULES_LOAD BOARD_RECOVERY_KERNEL_MODULES_LOAD
 BOOT_KERNEL_MODULES RECOVERY_KERNEL_MODULES SYSTEM_KERNEL_MODULES TARGET_AUTO_COLLECT_KERNEL_MODULE_DEPS
 BOARD_KERNEL_MODULES_LOAD_ALLOW_MISSING BOARD_USES_QCOM_MERGE_DTBS_SCRIPT BOARD_DTB_CFG
 TARGET_MODULE_ALIASES BOARD_CUSTOM_DTBOIMG_MK BOARD_CUSTOM_DTBIMG_MK"
make -s --no-print-directory -f - BCFILE="$BC/BoardConfig.mk" OUTD="$BC" VARS="$VARS" <<'EOF'
include $(BCFILE)
$(foreach v,$(VARS),$(file >$(OUTD)/$(v),$(strip $($(v)))))
all: ;
EOF
b() { cat "$BC/$1"; }
for v in SYSTEM_KERNEL_MODULES TARGET_AUTO_COLLECT_KERNEL_MODULE_DEPS BOARD_USES_QCOM_MERGE_DTBS_SCRIPT \
         BOARD_DTB_CFG TARGET_MODULE_ALIASES BOARD_CUSTOM_DTBOIMG_MK BOARD_CUSTOM_DTBIMG_MK TARGET_KERNEL_CONFIG_EXT; do
	[ -z "$(b $v)" ] || { echo "$v is set: not handled by this script" >&2; exit 1; }
done
[ "$(b TARGET_KERNEL_MIXED_MODE)" = false ] || { echo "only TARGET_KERNEL_MIXED_MODE := false is handled" >&2; exit 1; }

KERNEL_SRC=$(b TARGET_KERNEL_SOURCE)
KERNEL_ARCH=arm64
KERNEL_OUT=$OBJ/KERNEL_OBJ
DTB_OUT=$OBJ/DTB_OBJ
DTBO_OUT=$OBJ/DTBO_OBJ
# kernel.mk: $(KERNEL_BUILD_OUT_PREFIX)$(call intermediates-dir-for,...), absolute with the standard out dir
MODULES_INTERMEDIATES=$T/$OBJ/PACKAGING/kernel_modules_intermediates
TARGET_KERNEL_DTB=$(b TARGET_KERNEL_DTB); TARGET_KERNEL_DTB=${TARGET_KERNEL_DTB:-dtbs}
read -r -a KERNEL_DEFCONFIG <<< "$(b TARGET_KERNEL_CONFIG)"
ALL_KERNEL_DEFCONFIG_SRCS=()
for c in "${KERNEL_DEFCONFIG[@]}"; do ALL_KERNEL_DEFCONFIG_SRCS+=("$KERNEL_SRC/arch/$KERNEL_ARCH/configs/$c"); done

# ---------------------------------------------------------------------------
# Toolchain (config/BoardConfigKernel.mk)
if [ -n "$(b TARGET_KERNEL_CLANG_VERSION)" ]; then
	KERNEL_CLANG_VERSION=clang-$(b TARGET_KERNEL_CLANG_VERSION)
else
	KERNEL_CLANG_VERSION=$(python3 vendor/lineage/tools/get_clang_version.py)   # envsetup.sh
fi
RUST_VERSION=$(b TARGET_KERNEL_RUST_VERSION)
[ -n "$RUST_VERSION" ] || RUST_VERSION=$(grep 'RustDefaultVersion =' build/soong/rust/config/global.go | awk '{print $3}' | awk -F '"' '{print $2}')
CLANG_PATH=$T/prebuilts/clang/host/linux-x86/$KERNEL_CLANG_VERSION
if [ -f "$KERNEL_SRC/rust/bindings/bindings_helper.h" ]; then
	LIBCLANG_PATH=$(vendor/lineage/build/tools/select_kernel_libclang.sh \
		"$T/prebuilts/clang-tools/linux-x86/bin/bindgen" "$CLANG_PATH" "$T/prebuilts/clang/host/linux-x86")
else
	LIBCLANG_PATH=$CLANG_PATH/lib
fi
echo "clang: $KERNEL_CLANG_VERSION, rust: $RUST_VERSION, libclang: $LIBCLANG_PATH"
# Diagnostics: which libclang bindgen can use (the probe of select_kernel_libclang.sh)
BG=$T/prebuilts/clang-tools/linux-x86/bin/bindgen
echo "bindgen: $("$BG" --version 2>&1 | head -1)"
P=$(mktemp -d)
printf 'struct probe_a { struct probe_b *p; };\nstruct probe_b { int x; };\n' > "$P/probe.h"
for l in "$T"/prebuilts/clang/host/linux-x86/clang-*/lib; do
	o=$(LIBCLANG_PATH=$l LD_LIBRARY_PATH="$l:$CLANG_PATH/lib:$CLANG_PATH/lib64" "$BG" "$P/probe.h" --use-core \
		--no-layout-tests --no-doc-comments --formatter=none --no-include-path-detection --allowlist-type probe_b -- -x c 2>&1) || true
	case "$o" in *"struct probe_b"*"_address"*) r=opaque;; *"struct probe_b"*) r=ok;; *) r="fails: $(echo "$o" | head -2 | tr '\n' ' ')";; esac
	echo "  libclang $(basename "$(dirname "$l")") ($(head -1 "$(dirname "$l")/AndroidVersion.txt" 2>/dev/null)): $r"
done
for d in "$CLANG_PATH/bin" "$T/prebuilts/rust-toolchain/linux-x86/$RUST_VERSION/bin"; do
	[ -d "$d" ] || { echo "missing toolchain dir $d" >&2; exit 1; }
done

SYSROOT=
[ "$(b TARGET_KERNEL_LIBC_SYSROOT_USE)" = host ] || SYSROOT="--sysroot=$T/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8/sysroot"
KBT=$T/prebuilts/kernel-build-tools/linux-x86
BT=$T/prebuilts/build-tools/linux-x86
KERNEL_MAKE_FLAGS=(
	-j"$(getconf _NPROCESSORS_ONLN)"
	HOSTCFLAGS="$SYSROOT -I$KBT/include"
	HOSTLDFLAGS="$SYSROOT -Wl,-rpath,$KBT/lib64 -L $KBT/lib64 -fuse-ld=lld --rtlib=compiler-rt"
	LLVM=1 LLVM_IAS=1
	LZ4=$KBT/bin/lz4
	LEX=$BT/bin/flex YACC=$BT/bin/bison M4=$BT/bin/m4
	PAHOLE=$KBT/bin/pahole
	LIBCLANG_PATH="$LIBCLANG_PATH"
)
AFDO=$(b TARGET_KERNEL_CLANG_AUTOFDO_PROFILE)
if [ "$AFDO" != none ]; then
	AFDO=${AFDO:-$KERNEL_SRC/gki/aarch64/afdo/kernel.afdo}
	[ ! -e "$AFDO" ] || KERNEL_MAKE_FLAGS+=(CLANG_AUTOFDO_PROFILE="$T/$AFDO")
fi
[ "$(b BOARD_KERNEL_SEPARATED_DTBO)" != true ] || KERNEL_MAKE_FLAGS+=(DTC_EXT="$T/$HOST_OUT_EXECUTABLES/dtc")
if [ -n "$(b TARGET_KERNEL_KCONFIG_EXT_PREFIX)" ]; then
	KERNEL_MAKE_FLAGS+=(KCONFIG_EXT_PREFIX="$(python3 -c 'import os,sys;print(os.path.relpath(*(sys.argv[1:])))' "$(b TARGET_KERNEL_KCONFIG_EXT_PREFIX)" "$KERNEL_SRC")/")
fi
read -r -a ADD <<< "$(b TARGET_KERNEL_ADDITIONAL_FLAGS)"
KERNEL_MAKE_FLAGS+=("${ADD[@]}")
KERNEL_MAKE_CMD=$BT/bin/make
# CI diagnostics only (not what the ROM build does): keep going after errors
[ -z "$CI_KEEP_GOING" ] || KERNEL_MAKE_FLAGS+=(-k)

# PATH_OVERRIDE + TOOLS_PATH_OVERRIDE
export PATH=$T/$HOST_OUT_EXECUTABLES:$PATH
export LD_LIBRARY_PATH=$CLANG_PATH/lib64:$LD_LIBRARY_PATH
export PATH=$CLANG_PATH/bin:$PATH
export HIP_PATH=none PERL5LIB=$T/prebuilts/tools-lineage/common/perl-base
export PATH=$T/prebuilts/tools-lineage/linux-x86/bin:$BT/bin:$CLANG_PATH/bin:$T/prebuilts/rust-toolchain/linux-x86/$RUST_VERSION/bin:$T/prebuilts/clang-tools/linux-x86/bin:$PATH
export BISON_PKGDATADIR=$T/prebuilts/build-tools/common/bison
KERNEL_CC=(CC="clang" LD=ld.lld)

echo "KERNEL_MAKE_FLAGS:"; printf '  %s\n' "${KERNEL_MAKE_FLAGS[@]}"

kmake() { # O dir, targets...
	local o=$1; shift
	"$KERNEL_MAKE_CMD" "${KERNEL_MAKE_FLAGS[@]}" -C "$KERNEL_SRC" O="$T/$o" ARCH=$KERNEL_ARCH CLANG_TRIPLE=aarch64-linux-gnu- "${KERNEL_CC[@]}" "$@"
}
make_kernel_config() { # O dir
	local o=$1
	cp "${ALL_KERNEL_DEFCONFIG_SRCS[0]}" "$o/.config"
	kmake "$o" olddefconfig
	for c in "${ALL_KERNEL_DEFCONFIG_SRCS[@]}"; do
		case $c in *.config) ;; *) continue;; esac
		( cd "$T/$o" && "$T/$KERNEL_SRC/scripts/kconfig/merge_config.sh" -m -O "$T/$o" "$T/$o/.config" "$T/$c" )
		kmake "$o" olddefconfig
	done
	case "$(b KERNEL_LTO)" in
	none) "$KERNEL_SRC/scripts/config" --file "$o/.config" -d LTO_CLANG -e LTO_NONE -d LTO_CLANG_THIN -d LTO_CLANG_FULL -d THINLTO; kmake "$o" olddefconfig;;
	thin) "$KERNEL_SRC/scripts/config" --file "$o/.config" -e LTO_CLANG -d LTO_NONE -e LTO_CLANG_THIN -d LTO_CLANG_FULL -e THINLTO; kmake "$o" olddefconfig;;
	full) "$KERNEL_SRC/scripts/config" --file "$o/.config" -e LTO_CLANG -d LTO_NONE -d LTO_CLANG_THIN -e LTO_CLANG_FULL -d THINLTO; kmake "$o" olddefconfig;;
	esac
}

mkdir -p "$KERNEL_OUT" "$DTB_OUT" "$DTBO_OUT" "$MODULES_INTERMEDIATES"

# ---------------------------------------------------------------------------
step "Building Kernel Config"
make_kernel_config "$KERNEL_OUT"

step "Building Kernel Image ($(b BOARD_KERNEL_IMAGE_NAME))"
kmake "$KERNEL_OUT" "$(b BOARD_KERNEL_IMAGE_NAME)"
if [ -d "$KERNEL_SRC/arch/$KERNEL_ARCH/boot/dts/" ]; then
	step "Building DTBs"
	kmake "$KERNEL_OUT" dtbs
fi
grep -q '=m' "$KERNEL_OUT/.config"
step "Building Kernel Modules"
kmake "$KERNEL_OUT" modules
step "Installing Kernel Modules"
kmake "$KERNEL_OUT" INSTALL_MOD_PATH="$MODULES_INTERMEDIATES" INSTALL_MOD_STRIP=1 modules_install
if [ -n "$(b TARGET_KERNEL_EXT_MODULES)" ]; then
	step "Building and Installing External Kernel Modules"
	ROOT=$(b TARGET_KERNEL_EXT_MODULE_ROOT)
	rpath=$(python3 -c 'import os,sys;print(os.path.relpath(*(sys.argv[1:])))' "$ROOT" "$KERNEL_SRC")
	for p in $(b TARGET_KERNEL_EXT_MODULES); do
		[ "${p#*:}" = "$p" ] || { echo "kbuild-style external modules not handled" >&2; exit 1; }
		ext() { "$KERNEL_MAKE_CMD" "${KERNEL_MAKE_FLAGS[@]}" -C "$ROOT/$p" M="$rpath/$p" KERNEL_SRC="$T/$KERNEL_SRC" \
			OUT_DIR="$T/$KERNEL_OUT" O="$T/$KERNEL_OUT" ARCH=$KERNEL_ARCH CLANG_TRIPLE=aarch64-linux-gnu- "${KERNEL_CC[@]}" "$@"; }
		ext
		ext INSTALL_MOD_PATH="$MODULES_INTERMEDIATES" INSTALL_MOD_STRIP=1 KERNEL_UAPI_HEADERS_DIR="$KERNEL_OUT" modules_install
	done
fi

kernel_release=$(cat "$KERNEL_OUT/include/config/kernel.release")
kernel_modules_dir=$MODULES_INTERMEDIATES/lib/modules/$kernel_release
all_modules=$(find "$kernel_modules_dir" -type f -name '*.ko')
dup=$(echo "$all_modules" | xargs -n1 basename | sort | uniq -d)
[ -z "$dup" ] || { for m in $dup; do echo "ERROR: Duplicate module $m" >&2; done; exit 1; }

DEPMOD=$(command -v depmod)
# build-image-kernel-modules-lineage: modules, out dir, mount point, staging dir, load list
build_image_kernel_modules() {
	local mods=$1 out=$2 mp=$3 stage=$4 load=$5 ERROR=
	mkdir -p "$out/lib/modules"
	cp $mods "$out/lib/modules"
	rm -rf "$stage"
	mkdir -p "$stage/lib/modules/0.0/${mp}lib/modules"
	cp $mods "$stage/lib/modules/0.0/${mp}lib/modules"
	"$DEPMOD" -ae -F "$KERNEL_OUT/System.map" -b "$stage" 0.0 2>"$stage/depmod_stderr"
	cat "$stage/depmod_stderr" >&2
	if grep -q "needs unknown symbol" "$stage/depmod_stderr"; then
		echo "ERROR: kernel module(s) need unknown symbol(s)" >&2; exit 1
	fi
	sed -e 's/\(.*modules.*\):/\/\1:/g' -e 's/ \([^ ]*modules[^ ]*\)/ \/\1/g' "$stage/lib/modules/0.0/modules.dep" > "$out/lib/modules/modules.dep"
	cp "$stage/lib/modules/0.0/modules.softdep" "$stage/lib/modules/0.0/modules.alias" "$out/lib/modules"
	: > "$out/lib/modules/modules.load"
	for MODULE in $load; do
		NAME=$(basename "$MODULE" .ko)
		if [ -n "$(find "$out/lib/modules" -type f -name "$NAME.ko")" ]; then
			echo "$NAME" >> "$out/lib/modules/modules.load"
		else
			echo "ERROR: $NAME.ko was not found in the kernel modules intermediates dir" >&2
			[ "$(b BOARD_KERNEL_MODULES_LOAD_ALLOW_MISSING)" = true ] || ERROR=1
		fi
	done
	[ -z "$ERROR" ] || { echo "Module load list must be corrected." >&2; exit 1; }
	echo "$(echo $mods | wc -w) modules, $(wc -l < "$out/lib/modules/modules.load") in modules.load -> $out"
}
select_modules() { # list name, modules
	local what=$1; shift
	for m in "$@"; do
		p=$(echo "$all_modules" | grep "/$m" || true)
		[ -n "$p" ] || { echo "ERROR: $m from $what was not found" >&2; return 1; }
		echo "$p"
	done
}

if [ "$(b BOARD_USES_VENDOR_DLKMIMAGE)" = true ]; then
	MODULES_OUT=$PRODUCT_OUT/vendor_dlkm; MOUNTPOINT=vendor_dlkm/
else
	MODULES_OUT=$PRODUCT_OUT/vendor; MOUNTPOINT=vendor/
fi
step "Packaging $MODULES_OUT"
build_image_kernel_modules "$all_modules" "$MODULES_OUT" "$MOUNTPOINT" "$OBJ/PACKAGING/depmod_vendor_intermediates" "$(b BOARD_VENDOR_KERNEL_MODULES_LOAD)"
if [ -n "$(b BOOT_KERNEL_MODULES)" ]; then
	step "Packaging vendor_ramdisk"
	mods=$(select_modules BOOT_KERNEL_MODULES $(b BOOT_KERNEL_MODULES))
	build_image_kernel_modules "$mods" "$PRODUCT_OUT/vendor_ramdisk" "" "$OBJ/PACKAGING/depmod_vendor_ramdisk_intermediates" "$(b BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD)"
fi
if [ -n "$(b RECOVERY_KERNEL_MODULES)" ]; then
	step "Packaging recovery"
	RLOAD=$(b BOARD_RECOVERY_KERNEL_MODULES_LOAD); RLOAD=${RLOAD:-$(b BOARD_RECOVERY_RAMDISK_KERNEL_MODULES_LOAD)}
	mods=$(select_modules RECOVERY_KERNEL_MODULES $(b RECOVERY_KERNEL_MODULES))
	build_image_kernel_modules "$mods" "$PRODUCT_OUT/recovery/root" "" "$OBJ/PACKAGING/depmod_recovery_intermediates" "$RLOAD"
fi

# ---------------------------------------------------------------------------
if [ "$(b BOARD_INCLUDE_DTB_IN_BOOTIMG)" = true ]; then
	step "Building dtb.img"
	[ ! -d "$DTB_OUT/arch/$KERNEL_ARCH/boot/dts" ] || find "$DTB_OUT/arch/$KERNEL_ARCH/boot/dts" -type f -name "*.dtb" -delete
	make_kernel_config "$DTB_OUT"
	kmake "$DTB_OUT" "$TARGET_KERNEL_DTB"
	rm -f "$PRODUCT_OUT/dtb.img"
	for dtb in $(b TARGET_DTB_LIST_WILDCARD); do
		cat $(find "$DTB_OUT/arch/$KERNEL_ARCH/boot/dts/$(dirname "$dtb")/" -type f -name "$(basename "$dtb").dtb" | sort) >> "$PRODUCT_OUT/dtb.img"
	done
fi
if [ "$(b BOARD_KERNEL_SEPARATED_DTBO)" = true ]; then
	step "Building dtbo.img"
	[ ! -d "$DTBO_OUT/arch/$KERNEL_ARCH/boot/dts" ] || find "$DTBO_OUT/arch/$KERNEL_ARCH/boot/dts" -type f -name "*.dtbo" -delete
	kmake "$DTBO_OUT" "${KERNEL_DEFCONFIG[@]}"
	kmake "$DTBO_OUT" "$TARGET_KERNEL_DTB"
	if [ -n "$(b BOARD_DTBO_CFG)" ]; then
		"$HOST_OUT_EXECUTABLES/mkdtboimg" cfg_create "$PRODUCT_OUT/dtbo.img" "$(b BOARD_DTBO_CFG)" -d "$DTBO_OUT/arch/$KERNEL_ARCH/boot/dts"
	else
		"$HOST_OUT_EXECUTABLES/mkdtboimg" create "$PRODUCT_OUT/dtbo.img" --page_size="$(b BOARD_KERNEL_PAGESIZE)" \
			$(find "$DTBO_OUT/arch/$KERNEL_ARCH/boot/dts" -type f -name "*.dtbo" | sort)
	fi
fi
cp "$KERNEL_OUT/arch/$KERNEL_ARCH/boot/$(b BOARD_KERNEL_IMAGE_NAME)" "$PRODUCT_OUT/kernel"
step "Done: kernel $kernel_release"

# CI only, after everything the ROM build does: an Image for testing on a ROM
# that brings its own GKI modules (AnyKernel3 on PenguinOS). Those are signed
# by another build's key, which CONFIG_MODULE_SIG_PROTECT refuses for modules
# exporting protected GKI symbols (rfkill in vendor_boot: init gives up).
if [ -n "$CI_TEST_IMAGE" ]; then
	step "Test Image without CONFIG_MODULE_SIG_PROTECT (for other ROMs' modules)"
	# MODULE_SIG_PROTECT is def_bool y depending on a non-empty protect list
	"$KERNEL_SRC/scripts/config" --file "$KERNEL_OUT/.config" --set-str MODULE_SIG_PROTECT_LIST ""
	kmake "$KERNEL_OUT" olddefconfig
	kmake "$KERNEL_OUT" "$(b BOARD_KERNEL_IMAGE_NAME)"
	! grep -q "^CONFIG_MODULE_SIG_PROTECT=y" "$KERNEL_OUT/.config" || { echo "MODULE_SIG_PROTECT still set" >&2; exit 1; }
	cp "$KERNEL_OUT/arch/$KERNEL_ARCH/boot/$(b BOARD_KERNEL_IMAGE_NAME)" "$PRODUCT_OUT/kernel-test-nosigprotect"
fi
