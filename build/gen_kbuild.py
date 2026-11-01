#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Translate the techpack DDK (Bazel) module definitions into one Kbuild file.

redducc's 6.12 techpacks only describe their waipio build in Bazel (ddk_module,
ddk_submodule, ddk_headers, kconfig/defconfig). LineageOS builds kernels inline
with make, so this script evaluates those definitions for one target/variant
and writes build/kbuild/Kbuild: every module of qcom/opensource as a kbuild
composite object with per-object flags, plus one generated config header per
module (what DDK derives from the module's Kconfig and defconfig).

It is a development tool: the generated files are committed, the ROM build only
runs make. Re-run it after changing a techpack's Bazel files:

  gen_kbuild.py --starlark <starlark_check.py> --layout <layout.json> \
      --config <kernel .config> --modules <list of .ko names to build>
"""
import argparse
import importlib.util
import os
import re
import sys

ap = argparse.ArgumentParser()
ap.add_argument("--starlark", required=True)
ap.add_argument("--layout", required=True)
ap.add_argument("--config", required=True)
ap.add_argument("--modules", required=True, help="file with the .ko names to build, one per line")
ap.add_argument("--tv", default="waipio_perf")
ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "kbuild"))
args = ap.parse_args()

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)                      # sm8475-modules
ROOT = os.path.join(REPO, "qcom", "opensource")   # the kbuild M of all techpacks
PKG_PREFIXES = ("vendor/qcom/opensource/", "vendor/nothing/pong-modules/qcom/opensource/")
GLOBAL_PKGS = ("soc-repo", "msm-kernel", "common", "vendor/nothing/pong-kernel", "build/")

sys.setrecursionlimit(10000)
sys.argv = ["starlark_check.py", args.layout]
spec = importlib.util.spec_from_file_location("starlark", args.starlark)
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)

PACKAGES = sorted(os.path.relpath(os.path.dirname(p), ROOT)
                  for p in __import__("glob").glob(ROOT + "/**/BUILD.bazel", recursive=True))
for p in PACKAGES:
    h.eval_package("vendor/qcom/opensource/" + p)
if h.ERRORS:
    sys.exit("starlark errors:\n" + "\n".join(h.ERRORS))

KCONFIG = {}
for line in open(args.config):
    m = re.match(r"(CONFIG_\w+)=(.*)", line)
    if m:
        KCONFIG[m.group(1)] = m.group(2)

WANT = {l.strip().replace("-", "_") for l in open(args.modules) if l.strip()}


# ----------------------------------------------------------------------------
# labels and packages

def techpack_rel(pkg):
    """Package name -> path relative to qcom/opensource, or None if not a techpack."""
    for pre in PKG_PREFIXES:
        if pkg.startswith(pre):
            return pkg[len(pre):]
        if pkg + "/" == pre:
            return ""
    return None


def is_global(pkg):
    return pkg.startswith(GLOBAL_PKGS)


def resolve(label, pkg):
    if isinstance(label, str) and not label.startswith((":", "//", "@")) and label in h.PACKAGES.get(pkg, {}):
        label = ":" + label
    n = h.norm_label(label, pkg)
    if n is None:
        return None, None, None
    p, t = n
    if not is_global(p):
        h.eval_package(p)
    return p, t, h.PACKAGES.get(p, {}).get(t)


def pick(v):
    """Resolve a select() the way device.bazelrc configures the build."""
    if isinstance(v, h.Select) and not (len(v.parts) == 1 and v.parts[0] is v):
        vals = [pick(p) if not (isinstance(p, h.Select) and p.parts == [p]) else pick_one(p) for p in v.parts]
        if all(isinstance(x, dict) for x in vals):
            out = {}
            for x in vals:
                out.update(x)
            return out
        if all(isinstance(x, str) for x in vals):
            return "".join(vals)
        out = []
        for x in vals:
            out += x if isinstance(x, list) else [x]
        return out
    return pick_one(v)


def pick_one(v):
    if isinstance(v, h.Select):
        d = v.d
        for k in d:
            if "socrepo_true" in k or "qtisocrepo_true" in k:
                return pick(d[k])
        for k in d:
            if k.endswith(":arm64") or "android_arm64" in k or "aarch64" in k:
                return pick(d[k])
        for k in d:
            # camera-kernel's project_name flag defaults to "none"
            if k.endswith(":no_project"):
                return pick(d[k])
        if "//conditions:default" in d:
            return pick(d["//conditions:default"])
        return pick(next(iter(d.values())))
    return v


def plist(v):
    v = pick(v)
    if v is None:
        return []
    if isinstance(v, (list, tuple)):
        out = []
        for x in v:
            x = pick(x)
            out += x if isinstance(x, list) else [x]
        return out
    return [v]


def file_path(src, pkg):
    """A source/header/defconfig label -> absolute path, if it is a plain file."""
    if src.startswith("//") or src.startswith(":"):
        p, t, rec = resolve(src, pkg)
        if rec is not None:
            return None
        rel = techpack_rel(p)
        if rel is None:
            return None
        return os.path.normpath(os.path.join(ROOT, rel, t))
    rel = techpack_rel(pkg)
    return os.path.normpath(os.path.join(ROOT, rel, src))


def genrule_output(label, pkg):
    """Content of a `cat $(SRCS) > $@` genrule, or of a file."""
    if not label.startswith((":", "//")) and label in h.PACKAGES.get(pkg, {}):
        label = ":" + label
    p, t, rec = resolve(label, pkg) if label.startswith((":", "//")) else (pkg, label, None)
    if rec is None:
        path = file_path(label, pkg)
        if path and os.path.isfile(path):
            return open(path).read()
        # a genrule output file name
        for name, r in h.PACKAGES.get(p, {}).items():
            if name == "__evaluated__":
                continue
            outs = plist(r["kw"].get("outs")) + plist(r["kw"].get("out"))
            if t in outs:
                return genrule_output(":" + name, p)
        raise SystemExit(f"cannot resolve {label} in {pkg}")
    kw = rec["kw"]
    if rec["rule"] in ("genrule", "hermetic_genrule"):
        cmd = pick(kw.get("cmd"))
        text = "".join(genrule_output(s, p) + ("" if genrule_output(s, p).endswith("\n") else "\n")
                       for s in plist(kw.get("srcs")))
        if isinstance(cmd, str) and re.fullmatch(r"\s*cat \$\(SRCS\) > \$@\s*", cmd):
            return text
        if isinstance(cmd, str) and re.fullmatch(r"\s*cat \$\(SRCS\) \| sed -e 's/\^export //g' > \$@\s*", cmd):
            return re.sub(r"^export ", "", text, flags=re.M)
        raise SystemExit(f"unsupported genrule {label} ({cmd!r})")
    if rec["rule"] == "write_file":
        return "\n".join(plist(kw.get("content"))) + "\n"
    raise SystemExit(f"unsupported defconfig rule {rec['rule']} for {label}")


# ----------------------------------------------------------------------------
# headers

def headers(label, pkg, seen=None):
    """-> (include dirs, linux include dirs, module deps) provided by a dep label."""
    seen = seen if seen is not None else set()
    p, t, rec = resolve(label, pkg)
    if p is None or (p, t) in seen:
        return [], [], []
    seen.add((p, t))
    if is_global(p):
        return [], [], []
    if rec is None:
        return [], [], []
    kw = rec["kw"]
    rel = techpack_rel(p)
    inc, linc, mods = [], [], []
    if rec["rule"] in ("ddk_module",):
        mods.append((p, t))
    if rec["rule"] in ("ddk_headers", "ddk_module", "ddk_submodule"):
        inc += [os.path.normpath(os.path.join(ROOT, rel, d)) for d in plist(kw.get("includes"))]
        linc += [os.path.normpath(os.path.join(ROOT, rel, d)) for d in plist(kw.get("linux_includes"))]
        for hdr in plist(kw.get("hdrs")):
            if isinstance(hdr, str) and (hdr.startswith((":", "//")) or hdr in h.PACKAGES.get(p, {})):
                a, b, c = headers(hdr, p, seen)
                inc += a; linc += b; mods += c
        if rec["rule"] == "ddk_headers":
            for d in plist(kw.get("deps")):
                a, b, c = headers(d, p, seen)
                inc += a; linc += b; mods += c
    elif rec["rule"] in ("filegroup", "alias"):
        for s in plist(kw.get("srcs")) + plist(kw.get("actual")):
            if isinstance(s, str) and (s.startswith((":", "//")) or s in h.PACKAGES.get(p, {})):
                a, b, c = headers(s, p, seen)
                inc += a; linc += b; mods += c
    return inc, linc, mods


# ----------------------------------------------------------------------------
# module config (what DDK derives from kconfig + defconfig)

def config_inputs(pkg, kw, seen=None):
    """(Kconfig path, defconfig text) of a ddk_module and of its ddk_module deps.

    DDK merges the configuration of dependencies into a module's own."""
    seen = seen if seen is not None else set()
    out = []
    for d in plist(kw.get("deps")):
        if not isinstance(d, str):
            continue
        p, t, r = resolve(d, pkg)
        if r is None or r["rule"] != "ddk_module" or (p, t) in seen:
            continue
        seen.add((p, t))
        out += config_inputs(p, r["kw"], seen)
    if kw.get("kconfig"):
        dc = pick(kw.get("defconfig"))
        out.append((os.path.join(ROOT, techpack_rel(pkg), pick(kw["kconfig"])),
                    genrule_output(dc, pkg) if dc else ""))
    return out


def module_config(inputs):
    import kconfiglib
    texts = [open(k).read() for k, _ in inputs]
    defined = set()
    for t in texts:
        defined |= set(re.findall(r"^\s*(?:menu)?config\s+(\w+)", t, re.M))
    refs = set()
    for t in texts:
        refs |= set(re.findall(r"\b([A-Z][A-Z0-9_]+)\b", t))
    refs -= defined
    stub = []
    for s in sorted(refs):
        v = KCONFIG.get("CONFIG_" + s)
        if v in ("y", "m"):
            stub.append(f"config {s}\n\tdef_tristate {v}\n")
    tmp = os.path.join("/tmp", "gen_kbuild_Kconfig")
    with open(tmp, "w") as f:
        f.write("config MODULES\n\tdef_bool y\n\toption modules\n")
        f.write("".join(stub))
        for k, _ in inputs:
            f.write(f'source "{k}"\n')
    os.environ["srctree"] = "/"
    kc = kconfiglib.Kconfig(tmp, warn=False)
    dtmp = tmp + ".defconfig"
    open(dtmp, "w").write("".join(d if d.endswith("\n") or not d else d + "\n" for _, d in inputs))
    kc.load_config(dtmp, replace=True)
    vals = {}
    for name in defined:
        sym = kc.syms.get(name)
        if sym is None or not sym.str_value or sym.str_value == "n":
            continue
        vals["CONFIG_" + name] = '"' + sym.str_value + '"' if sym.type == kconfiglib.STRING else sym.str_value
    return vals


def config_header(vals):
    lines = []
    for k, v in sorted(vals.items()):
        if v == "y":
            lines.append(f"#define {k} 1")
        elif v == "m":
            lines.append(f"#define {k}_MODULE 1")
        else:
            lines.append(f"#define {k} {v}")
    return "\n".join(lines) + "\n"


# ----------------------------------------------------------------------------
# units (one .ko each)

class Unit:
    pass


def conditional(cs, cfg):
    out = []
    for opt, branches in (pick(cs) or {}).items():
        val = cfg.get(opt, KCONFIG.get(opt, "n"))
        on = val in ("y", "m") or (val not in ("n", "") and not val.startswith("n"))
        branches = pick(branches)
        out += plist(branches.get(on, branches.get(str(on), [])))
    return out


def make_unit(pkg, rec, parent_kw, cfg, parent_pkg=None):
    kw = rec["kw"]
    u = Unit()
    u.pkg = pkg
    u.name = kw["name"]
    u.out = plist(kw.get("out"))[0]
    rel = techpack_rel(pkg)
    srcs = []
    for s in plist(kw.get("srcs")) + conditional(kw.get("conditional_srcs"), cfg):
        path = file_path(s, pkg)
        if path is None:
            # generated header: drop, the content is produced separately
            srcs.append(("gen", s))
        else:
            srcs.append(("file", path))
    u.srcs = srcs
    u.cfg = cfg
    deps = plist(kw.get("deps")) + plist((parent_kw or {}).get("deps"))
    inc = [os.path.normpath(os.path.join(ROOT, rel, d)) for d in plist(kw.get("includes"))]
    linc = []
    mods = []
    for d in deps:
        if not isinstance(d, str):
            continue
        p, t, r = resolve(d, pkg)
        if r is not None and r["rule"] == "ddk_submodule":
            continue
        if r is None and p is not None and not is_global(p):
            UNRESOLVED.add(f"{pkg}:{kw['name']} -> {d}")
        a, b, c = headers(d, pkg)
        inc += a; linc += b; mods += c
    u.includes = list(dict.fromkeys(inc))
    u.linux_includes = list(dict.fromkeys(linc))
    u.defines = plist(kw.get("local_defines")) + plist((parent_kw or {}).get("local_defines"))
    u.copts = anchor_copts([expand_copt(c, pkg) for c in plist(kw.get("copts"))
                            if isinstance(c, str)], pkg)
    if parent_kw:
        u.copts += anchor_copts([expand_copt(c, parent_pkg) for c in plist(parent_kw.get("copts"))
                                 if isinstance(c, str)], parent_pkg)
    for kind, s in srcs:
        if kind == "gen" and isinstance(s, str) and s.endswith(("grep_defines",)):
            genrule_script(s, pkg)
    return u


GENRULES = {}
UNRESOLVED = set()


def genrule_script(label, pkg):
    """A build-time genrule (date banner, header probes) -> its output name."""
    p, t, rec = resolve(label, pkg)
    if rec is not None and rec["rule"] == "ddk_headers":
        hdrs = [x for x in plist(rec["kw"].get("hdrs")) if isinstance(x, str)]
        if len(hdrs) != 1:
            raise SystemExit(f"cannot expand {label}")
        return genrule_script(hdrs[0], p)
    if rec is None or rec["rule"] not in ("genrule", "hermetic_genrule"):
        raise SystemExit(f"cannot expand {label} ({rec and rec['rule']})")
    out = os.path.basename(plist(rec["kw"].get("outs"))[0])
    cmd = pick(rec["kw"].get("cmd"))
    cmd = re.sub(r"\$\(location //common:([^)]+)\)", r'"$KERNEL_SRC/\1"', cmd)
    if "$(" in cmd.replace("$$(", ""):
        raise SystemExit(f"unsupported make variable in genrule {label}")
    cmd = cmd.replace("$$", "$").replace('"$@"', '"$OUT"').replace("$@", '"$OUT"')
    GENRULES[out] = (f"# {p}:{t}\nOUT=\"$G/{out}.tmp\"\n(\n{cmd.strip()}\n)\n"
                     f"if cmp -s \"$OUT\" \"$G/{out}\"; then rm \"$OUT\"; else mv \"$OUT\" \"$G/{out}\"; fi\n")
    return out


def expand_copt(c, pkg):
    return re.sub(r"\$\(location ([^)]+)\)", lambda m: "$(T)/build/genrules/" + genrule_script(m.group(1), pkg), c)


def anchor_copts(copts, pkg):
    """DDK resolves the paths of -include/-I options relative to the package."""
    rel = techpack_rel(pkg)
    out = []
    prev = None
    for c in copts:
        if prev in ("-include", "-I", "-isystem", "-iquote") and not c.startswith(("/", "$(")):
            c = f"$(T)/{rel}/{c}"
        elif c.startswith("-I") and len(c) > 2 and not c[2:].startswith(("/", "$(")):
            c = f"-I$(T)/{rel}/{c[2:]}"
        out.append(c)
        prev = c
    return out


units = []
for pkg in sorted(h.PACKAGES):
    if techpack_rel(pkg) is None or pkg.startswith("vendor/nothing/"):
        continue
    for name, rec in h.PACKAGES[pkg].items():
        if name == "__evaluated__" or rec["rule"] != "ddk_module" or not name.startswith(args.tv + "_"):
            continue
        kw = rec["kw"]
        subs = []
        for d in plist(kw.get("deps")):
            p, t, r = resolve(d, pkg) if isinstance(d, str) else (None, None, None)
            if r is not None and r["rule"] == "ddk_submodule":
                subs.append((p, r))
        # Like Bazel, only analyse the modules that are built: the Bazel files
        # of some techpacks define waipio modules whose inputs do not exist
        # (mm-drivers hw_fence has no waipio_defconfig).
        outs = [pick_one(kw.get("out"))] + [pick_one(r["kw"].get("out")) for p, r in subs]
        if not any(isinstance(o, str) and o[:-3].replace("-", "_") in WANT for o in outs):
            continue
        cfg = {}
        inputs = config_inputs(pkg, kw)
        if inputs:
            cfg = module_config(inputs)
        if kw.get("out"):
            units.append(make_unit(pkg, rec, None, cfg))
        for p, r in subs:
            units.append(make_unit(p, r, kw, cfg, pkg))

units = [u for u in units if u.out[:-3].replace("-", "_") in WANT]
missing = WANT - {u.out[:-3].replace("-", "_") for u in units}

# ----------------------------------------------------------------------------
# write Kbuild

os.makedirs(args.out, exist_ok=True)
for f in os.listdir(args.out):
    os.remove(os.path.join(args.out, f))


def mrel(path):
    return os.path.relpath(path, ROOT)


k = []
k.append("# SPDX-License-Identifier: GPL-2.0")
k.append("# Generated by build/gen_kbuild.py from the techpack Bazel files (%s). Do not edit." % args.tv)
k.append("")
k.append("T := $(abspath $(src))")
k.append("")
k.append("# Clang newer than the kleaf toolchain checks snprintf truncation, which the")
k.append("# NL_SET_ERR_MSG_FMT_MOD helpers of include/net/flow_offload.h trip on for")
k.append("# modules with long names (rmnet_perf_tether). GCC builds of the kernel")
k.append("# already disable it (scripts/Makefile.extrawarn).")
k.append("ccflags-y += $(call cc-disable-warning, format-truncation)")
k.append("G := $(T)/build/kbuild")
k.append("")
owner = {}
for u in sorted(units, key=lambda u: u.out):
    mod = u.out[:-3]
    stem = re.sub(r"\W", "_", mod)
    if u.cfg:
        open(os.path.join(args.out, f"config_{stem}.h"), "w").write(
            "/* SPDX-License-Identifier: GPL-2.0 */\n/* %s: values of its Kconfig with its defconfig */\n" % u.out
            + config_header(u.cfg))
    flags = []
    if u.cfg:
        flags.append(f"-include $(G)/config_{stem}.h")
    flags += [f"-I$(T)/{mrel(d)}" for d in u.linux_includes + u.includes]
    # Trace include paths are given relative to the kernel's include/trace in
    # the Bazel layout (../../../../../vendor/qcom/opensource/<techpack>/...)
    flags += [f"-D{re.sub(r'=(?:\.\./)+vendor/(?:nothing/pong-modules/)?qcom/opensource/', '=$(T)/', d)}"
              for d in u.defines]
    flags += [c for c in u.copts if isinstance(c, str)]
    objs = []
    pkgdir = os.path.join(ROOT, techpack_rel(u.pkg))
    for kind, s in u.srcs:
        if kind != "file":
            continue
        if s.endswith((".c", ".S")):
            obj = mrel(s)[:-2] + ".o"
            if obj in owner and owner[obj] != mod:
                # same source in two modules: compile a second copy through a wrapper
                w = f"{stem}__{os.path.basename(s)}"
                open(os.path.join(args.out, w), "w").write(f'#include "{os.path.relpath(s, args.out)}"\n')
                obj = f"build/kbuild/{w[:-2]}.o"
            if obj in objs:
                # listed twice in the Bazel srcs (qcacld-3.0): build it once,
                # and do not double its flags, which would make the command
                # lines of qca_cld3 too long for deep build trees
                continue
            owner[obj] = mod
            objs.append(obj)
        elif s.endswith(".o_shipped") or s.endswith(".o"):
            objs.append(mrel(s).replace(".o_shipped", ".o"))
    modpath = os.path.join(mrel(pkgdir), mod) if mrel(pkgdir) != "." else mod
    if modpath + ".o" in objs:
        # kbuild cannot link a composite object that lists itself
        if objs == [modpath + ".o"]:
            objs = []
        else:
            w = f"{stem}__main.c"
            open(os.path.join(args.out, w), "w").write(f'#include "{os.path.relpath(os.path.join(ROOT, modpath + ".c"), args.out)}"\n')
            objs[objs.index(modpath + ".o")] = f"build/kbuild/{w[:-2]}.o"
    k.append(f"# {u.out}  ({u.pkg}:{u.name})")
    k.append(f"obj-m += {modpath}.o")
    if objs:
        k.append(f"{modpath}-y := " + " ".join(objs))
    k.append(f"FLAGS_{stem} := " + " ".join(flags))
    for o in objs or [modpath + ".o"]:
        k.append(f"CFLAGS_{o[:-2]}.o += $(FLAGS_{stem})")
        k.append(f"AFLAGS_{o[:-2]}.o += $(FLAGS_{stem})")
    k.append("")

open(os.path.join(args.out, "Kbuild"), "w").write("\n".join(k) + "\n")
with open(os.path.join(args.out, "genrules.sh"), "w") as f:
    f.write("#!/bin/sh\n# SPDX-License-Identifier: GPL-2.0\n"
            "# Generated by build/gen_kbuild.py: the build-time genrules of the techpacks.\n"
            "# usage: KERNEL_SRC=<kernel source> genrules.sh <output dir>\n"
            "set -e\nG=$1\nmkdir -p \"$G\"\n\n" + "\n".join(GENRULES[o] for o in sorted(GENRULES)))
for x in sorted(UNRESOLVED):
    print("WARNING: unresolved dep", x)
print(f"{len(units)} modules; not found in the Bazel files: {' '.join(sorted(missing)) or 'none'}")
