#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Predict whether a ROM's kernel modules load on the kernel built here.

For flashing just this kernel's Image onto a ROM that ships its own modules
(an AnyKernel3 test), every module of the ROM's vendor_dlkm and vendor_boot
must load on the new Image. The checks follow the 6.12 module loader:
  - vermagic: with CONFIG_MODVERSIONS only the part after the release is
    compared (SMP preempt mod_unload modversions aarch64)
  - each import of a vmlinux symbol needs the symbol exported with the same
    CRC (Module.symvers of this build)
  - ANDROID GKI: a module whose signature this kernel cannot verify (its
    GKI modules were signed by another build's key) is a vendor module and
    may only import vmlinux symbols on the permitted list
    (.vmlinux.permitted-imports.c, CONFIG_TRIM_UNUSED_KSYMS)
  - CONFIG_MODULE_SIG_PROTECT: such a module may not export a symbol of a
    protected GKI module (android/protected_module_names_list): rfkill.ko
    of the ROM, exporting rfkill_alloc, fails like that and, being in
    vendor_boot, makes first stage init give up (kernel panic)
  - symbols exported by other modules of the ROM resolve among themselves

usage: check_rom_modules.py <Module.symvers> <.vmlinux.permitted-imports.c>
                            <protected_module_names_list> <this kernel's vermagic>
                            <rom modules dir>...
"""
import glob
import os
import re
import subprocess
import sys

symvers, permitted_c, protected_list, vermagic = sys.argv[1:5]
dirs = sys.argv[5:]

vmlinux = {}
for line in open(symvers):
    crc, sym, owner = line.split("\t")[:3]
    if owner.endswith("vmlinux"):
        vmlinux[sym] = int(crc, 16)
permitted = set(re.findall(r'"([^"]+)"', open(permitted_c).read()))
# exports of the protected GKI modules (what modpost puts in
# .vmlinux.protected-exports.c), from Module.symvers of this build
protected_mods = {l.strip().rsplit("/", 1)[-1] for l in open(protected_list) if l.strip()}
protected_exports = set()
for line in open(symvers):
    crc, sym, owner = line.split("\t")[:3]
    if owner.rsplit("/", 1)[-1] in protected_mods:
        protected_exports.add(sym)
want_magic = vermagic.split(" ", 1)[1]


def run(*a):
    return subprocess.run(a, capture_output=True, text=True).stdout


mods = {}
for d in dirs:
    for p in sorted(glob.glob(d + "/**/*.ko", recursive=True)):
        mods.setdefault(os.path.basename(p), p)

exported_by_modules = set()
for p in mods.values():
    nm = run(os.environ.get("LLVM_NM", "llvm-nm"), p)
    exported_by_modules |= {l.split()[-1][len("__ksymtab_"):] for l in nm.splitlines() if " __ksymtab_" in l}

problems = {}
signed = 0
for name, p in sorted(mods.items()):
    issues = []
    magic = run("modinfo", "-F", "vermagic", p).strip()
    if magic.split(" ", 1)[1:] != [want_magic]:
        issues.append(f"vermagic '{magic}'")
    is_signed = bool(run("modinfo", "-F", "signer", p).strip())
    signed += is_signed
    if is_signed:
        nm = run(os.environ.get("LLVM_NM", "llvm-nm"), p)
        exp = {l.split()[-1][len("__ksymtab_"):] for l in nm.splitlines() if " __ksymtab_" in l}
        bad = sorted(exp & protected_exports)
        if bad:
            issues.append(f"exports protected symbol {bad[0]} (signed by another key)")
    for line in run("modprobe", "--dump-modversions", p).splitlines():
        crc, sym = line.split()[:2]
        if sym == "module_layout":
            continue
        if sym in vmlinux:
            if int(crc, 16) != vmlinux[sym]:
                issues.append(f"CRC of {sym}")
            elif is_signed and sym not in permitted:
                issues.append(f"{sym} not permitted for a module signed by another key")
        elif sym not in exported_by_modules:
            issues.append(f"{sym} exported by nothing")
    if issues:
        problems[name] = issues

print(f"{len(mods)} ROM modules checked ({signed} signed by the ROM kernel's build key)")
if not problems:
    print("all of them should load on this kernel")
for name, issues in problems.items():
    print(f"  WOULD FAIL {name}: " + "; ".join(issues[:6]) + (f" (+{len(issues) - 6})" if len(issues) > 6 else ""))
