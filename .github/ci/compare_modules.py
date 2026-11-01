#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Compare a module install dir with a reference build (redducc's kleaf 6.12 modules):
module set, dependencies, parameters, aliases, exports, imports and import CRCs.

usage: compare_modules.py <our modules dir> <reference dir>"""
import glob
import os
import subprocess
import sys
from collections import Counter

ours_dir, ref_dir = sys.argv[1], sys.argv[2]


def norm(p):
    return os.path.basename(p)[:-3].replace("-", "_")


def collect(d):
    out = {}
    for p in glob.glob(d + "/**/*.ko", recursive=True):
        out.setdefault(norm(p), p)
    return out


def modinfo(p, field):
    r = subprocess.run(["modinfo", "-F", field, p], capture_output=True, text=True).stdout
    return [x for x in r.splitlines() if x]


def versions(p):
    r = subprocess.run(["modprobe", "--dump-modversions", p], capture_output=True, text=True).stdout
    return {l.split()[1]: l.split()[0] for l in r.splitlines() if l.strip()}


def exports(p):
    r = subprocess.run([os.environ.get("LLVM_NM", "llvm-nm"), p], capture_output=True, text=True).stdout
    return {l.split()[-1][len("__ksymtab_"):] for l in r.splitlines() if " __ksymtab_" in l}


ours, ref = collect(ours_dir), collect(ref_dir)
print(f"ours {len(ours)} modules, prebuilt {len(ref)}")
print("only prebuilt:", " ".join(sorted(set(ref) - set(ours))) or "-")
print("only ours:", " ".join(sorted(set(ours) - set(ref))) or "-")

stats = Counter()
issues = []
for m in sorted(set(ref) & set(ours)):
    a, b = ours[m], ref[m]
    da = sorted(x.replace("-", "_") for x in ",".join(modinfo(a, "depends")).split(",") if x)
    db = sorted(x.replace("-", "_") for x in ",".join(modinfo(b, "depends")).split(",") if x)
    if da != db:
        issues.append(f"{m}: depends ours={da} ref={db}")
        stats["depends"] += 1
    pa, pb = sorted(modinfo(a, "parm")), sorted(modinfo(b, "parm"))
    if [x.split(":")[0] for x in pa] != [x.split(":")[0] for x in pb]:
        issues.append(f"{m}: parameters differ")
        stats["parm"] += 1
    if sorted(modinfo(a, "alias")) != sorted(modinfo(b, "alias")):
        issues.append(f"{m}: aliases differ")
        stats["alias"] += 1
    ea, eb = exports(a), exports(b)
    if ea != eb:
        issues.append(f"{m}: exports only ours={sorted(ea - eb)[:6]} only ref={sorted(eb - ea)[:6]}")
        stats["exports"] += 1
    va, vb = versions(a), versions(b)
    if set(va) != set(vb):
        issues.append(f"{m}: imports only ours={sorted(set(va) - set(vb))[:6]} only ref={sorted(set(vb) - set(va))[:6]}")
        stats["imports"] += 1
    bad = [s for s in set(va) & set(vb) if va[s] != vb[s] and s != "module_layout"]
    if bad:
        issues.append(f"{m}: {len(bad)} import CRCs differ, e.g. {sorted(bad)[:4]}")
        stats["crc"] += 1
    stats["compared"] += 1

for i in issues:
    print("  ", i)
print(dict(stats))
