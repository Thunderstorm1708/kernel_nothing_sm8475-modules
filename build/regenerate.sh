#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# Regenerate the Kbuild files of the make (LineageOS inline) build from the
# Bazel files of soc-repo and the techpacks. Run after changing them, then
# commit the result.
#
# usage: build/regenerate.sh <kernel/nothing/sm8475> <kernel .config of the device>
#   (the .config of a build of this kernel with its device fragments)
set -e
REPO=$(cd "$(dirname "$0")/.." && pwd)
KERNEL=$(cd "$1" && pwd)
CONFIG=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
LAYOUT=$(mktemp)
trap 'rm -f "$LAYOUT"' EXIT
cat > "$LAYOUT" <<EOJ
{
 "common": "$KERNEL",
 "soc-repo": "$REPO/soc-repo",
 "msm-kernel": "$REPO/soc-repo",
 "build/qcom_build_extensions": "$REPO/soc-repo/qcom_build_extensions",
 "vendor/nothing/pong-kernel": "$REPO/soc-repo",
 "vendor/nothing/pong-modules": "$REPO",
 "vendor/qcom/opensource": "$REPO/qcom/opensource"
}
EOJ
python3 "$REPO/soc-repo/build/gen_kbuild.py" --starlark "$REPO/build/starlark_eval.py" --layout "$LAYOUT" --config "$CONFIG"
python3 "$REPO/build/gen_kbuild.py" --starlark "$REPO/build/starlark_eval.py" --layout "$LAYOUT" --config "$CONFIG" \
	--modules "$REPO/build/techpack_modules.txt"
