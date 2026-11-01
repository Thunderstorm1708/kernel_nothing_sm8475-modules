#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# Fetch the parts of a LineageOS tree the kernel build uses, at the revisions
# of the LineageOS manifest (default: lineage-24.0): vendor/lineage,
# build/soong's Rust version, and the clang, rust, clang-tools, build-tools,
# kernel-build-tools and tools-lineage prebuilts (sparse, only what is used),
# plus mkdtboimg. Run from the top of the tree.
set -eo pipefail
BRANCH=${LINEAGE_BRANCH:-lineage-24.0}
GH=https://github.com/LineageOS
AOSP=https://android.googlesource.com
M=$(mktemp -d)
curl -sfL "https://raw.githubusercontent.com/LineageOS/android/$BRANCH/default.xml" -o "$M/default.xml"
curl -sfL "https://raw.githubusercontent.com/LineageOS/android/$BRANCH/snippets/lineage.xml" -o "$M/lineage.xml"

# revision of a project path in the manifest
rev() {
	python3 - "$M" "$1" <<'EOF'
import sys, xml.etree.ElementTree as ET
d, path = sys.argv[1], sys.argv[2]
remotes, default, projects = {}, {}, {}
for f in ("default.xml", "lineage.xml"):
    r = ET.parse(f"{d}/{f}").getroot()
    for e in r.findall("remote"):
        remotes[e.get("name")] = e.attrib
    if r.find("default") is not None:
        default = r.find("default").attrib
    for p in r.findall("project"):
        projects[p.get("path") or p.get("name")] = p.attrib
p = projects[path]
remote = p.get("remote", default.get("remote"))
print(p.get("revision") or remotes.get(remote, {}).get("revision") or default["revision"])
EOF
}

sparse() { # dir url revision patterns...
	local dir=$1 url=$2 r=$3; shift 3
	echo "== $dir ($r): $*"
	rm -rf "$dir"; mkdir -p "$dir"
	git -C "$dir" init -q
	git -C "$dir" remote add origin "$url"
	git -C "$dir" sparse-checkout set --no-cone "$@"
	git -C "$dir" fetch -q --depth=1 --filter=blob:none origin "$r"
	git -C "$dir" checkout -q FETCH_HEAD
	du -sh "$dir"
}

git clone -q --depth=1 -b "$(rev vendor/lineage | sed 's|refs/heads/||')" $GH/android_vendor_lineage vendor/lineage
mkdir -p build/soong/rust/config
curl -sfL "https://raw.githubusercontent.com/LineageOS/android_build_soong/$(rev build/soong | sed 's|refs/heads/||')/rust/config/global.go" \
	-o build/soong/rust/config/global.go

CLANG=$(python3 vendor/lineage/tools/get_clang_version.py)
RUST=$(grep 'RustDefaultVersion =' build/soong/rust/config/global.go | awk '{print $3}' | awk -F '"' '{print $2}')
echo "clang $CLANG, rust $RUST"

sparse prebuilts/clang/host/linux-x86 $AOSP/platform/prebuilts/clang/host/linux-x86 \
	"$(rev prebuilts/clang/host/linux-x86)" "/$CLANG/"
sparse prebuilts/rust-toolchain/linux-x86 $AOSP/platform/prebuilts/rust-toolchain/linux-x86 \
	"$(rev prebuilts/rust-toolchain/linux-x86)" "/$RUST/"
sparse prebuilts/clang-tools $AOSP/platform/prebuilts/clang-tools \
	"$(rev prebuilts/clang-tools)" "/linux-x86/bin/bindgen" "/linux-x86/lib64/"
sparse prebuilts/build-tools $AOSP/platform/prebuilts/build-tools \
	"$(rev prebuilts/build-tools)" "/linux-x86/bin/make" "/linux-x86/bin/flex" "/linux-x86/bin/bison" \
	"/linux-x86/bin/m4" "/linux-x86/lib64/" "/common/bison/"
sparse prebuilts/kernel-build-tools $AOSP/kernel/prebuilts/build-tools \
	"$(rev prebuilts/kernel-build-tools)" "/linux-x86/"
sparse prebuilts/tools-lineage $GH/android_prebuilts_tools-lineage \
	"$(rev prebuilts/tools-lineage)" "/linux-x86/bin/" "/common/perl-base/"
sparse "$M/libufdt" $GH/android_system_libufdt "$(rev system/libufdt)" "/utils/src/mkdtboimg.py"

# host tools the ROM build makes from source (out/host): mkdtboimg, dtc
mkdir -p out/host/linux-x86/bin
install -m 755 "$M/libufdt/utils/src/mkdtboimg.py" out/host/linux-x86/bin/mkdtboimg
ln -sf "$(command -v dtc)" out/host/linux-x86/bin/dtc
