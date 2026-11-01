#!/usr/bin/env python3
"""Evaluate Bazel BUILD/.bzl files of a kernel platform layout with stubbed rules (for gen_kbuild.py).

Records every target each package defines and every label referenced from rule
attributes, then reports labels that do not resolve. This is a static stand-in
for `bazel query` when Bazel and the kleaf rules are not available.
"""
import fnmatch
import glob as _glob
import json
import os
import re
import sys
import types

LAYOUT = json.load(open(sys.argv[1]))  # {"label/path": "/fs/dir", ...}
ROOTS = sorted(LAYOUT.items(), key=lambda kv: -len(kv[0]))
STUB_PREFIXES = ("build/kernel", "build/bazel_common_rules", "@", "conditions", "prebuilts", "external", "bootable", "common-modules", "tools")  # kleaf rules, not available here


def fs_dir(pkg):
    for lp, d in ROOTS:
        if pkg == lp or pkg.startswith(lp + "/"):
            return os.path.join(d, pkg[len(lp):].lstrip("/"))
    return None


class Depset:
    def __init__(self, direct=None, transitive=None, **k):
        self.items = list(direct or [])
        for d in transitive or []:
            self.items += d.to_list() if isinstance(d, Depset) else list(d)

    def to_list(self):
        return list(dict.fromkeys(self.items))


class Fail(Exception):
    pass


class Select:
    """select(); `+`/`|` with other values are kept in .parts (in order)."""
    def __init__(self, d, parts=None):
        self.d = d
        self.parts = parts if parts is not None else [self]

    def _join(self, a, b):
        pa = a.parts if isinstance(a, Select) else [a]
        pb = b.parts if isinstance(b, Select) else [b]
        return Select(self.d, pa + pb)

    def __add__(self, o):
        return self._join(self, o)

    def __radd__(self, o):
        return self._join(o, self)

    def __or__(self, o):
        return self._join(self, o)

    def __ror__(self, o):
        return self._join(o, self)


class Anything:
    """Stand-in for values coming from stubbed rules (providers, structs...)."""
    def __getattr__(self, k):
        return Anything()

    def __call__(self, *a, **k):
        return Anything()

    def __iter__(self):
        return iter([])

    def __bool__(self):
        return False

    def __add__(self, o):
        return o

    def __radd__(self, o):
        return o


PACKAGES = {}      # pkg -> {target: {"rule":..., "kw":...}}
REFS = []          # (pkg, target, attr, label)
FILES = {}         # cached .bzl module namespaces
ERRORS = []
CUR = []           # stack of package names being evaluated


def norm_label(label, pkg):
    if label.startswith("@"):
        return None
    if label.startswith("//"):
        body = label[2:]
        if ":" in body:
            p, t = body.split(":", 1)
        else:
            p, t = body, body.split("/")[-1]
        return p, t
    if label.startswith(":"):
        return pkg, label[1:]
    return None


def record_rule(rule):
    def f(*args, **kw):
        pkg = CUR[-1] if CUR else None
        name = kw.get("name")
        if pkg is not None and name is not None:
            PACKAGES.setdefault(pkg, {})[name] = {"rule": rule, "kw": kw}
            for attr, v in kw.items():
                if attr in ("name", "visibility", "cmd", "content", "copts", "local_defines", "kconfig", "defconfig_fragments"):
                    continue
                for s in walk_strings(v):
                    if s.startswith("//") or (s.startswith(":") and len(s) > 1):
                        REFS.append((pkg, name, attr, s))
        return Anything()
    return f


def walk_strings(v):
    if isinstance(v, str):
        yield v
    elif isinstance(v, (list, tuple, set)):
        for x in v:
            yield from walk_strings(x)
    elif isinstance(v, dict):
        for k, x in v.items():
            yield from walk_strings(k)
            yield from walk_strings(x)
    elif isinstance(v, Select):
        for part in v.parts:
            if part is v or (isinstance(part, Select) and part.parts == [part]):
                yield from walk_strings(part.d)
            else:
                yield from walk_strings(part)


class Native(types.SimpleNamespace):
    def __getattr__(self, k):
        if k == "package_name":
            return lambda: CUR[-1]
        if k == "glob":
            return do_glob
        if k == "existing_rule":
            return lambda n: PACKAGES.get(CUR[-1], {}).get(n)
        if k == "existing_rules":
            return lambda: dict(PACKAGES.get(CUR[-1], {}))
        if k == "repository_name":
            return lambda: "@"
        return record_rule(k)


def do_glob(include, exclude=None, allow_empty=True, exclude_directories=1):
    pkg = CUR[-1]
    base = fs_dir(pkg)
    out = []
    for pat in include:
        g = _glob.glob(os.path.join(base, pat), recursive=True)
        for f in g:
            if os.path.isdir(f) and exclude_directories:
                continue
            rel = os.path.relpath(f, base)
            if any(fnmatch.fnmatch(rel, e) for e in (exclude or [])):
                continue
            out.append(rel)
    return sorted(set(out))


def struct(**kw):
    return types.SimpleNamespace(**kw)


def builtins_for(pkg_of_file):
    def load(path, *syms, **aliases):
        ns = load_bzl(path, pkg_of_file)
        g = sys._getframe(1).f_globals
        for s in syms:
            g[s] = ns.get(s, Anything())
        for a, s in aliases.items():
            g[a] = ns.get(s, Anything())

    def fail(*a, **k):
        raise Fail(" ".join(str(x) for x in a))

    def sl_type(x):
        return {list: "list", dict: "dict", str: "string", int: "int", bool: "bool", tuple: "tuple",
                type(None): "NoneType", types.SimpleNamespace: "struct", Select: "select"}.get(
                    type(x), "function" if callable(x) else type(x).__name__)

    b = {
        "type": sl_type,
        "load": load, "fail": fail, "struct": struct, "select": Select,
        "glob": do_glob, "native": Native(), "Label": lambda s: s,
        "package_name": lambda: CUR[-1], "repository_name": lambda: "@",
        "package_relative_label": lambda s: types.SimpleNamespace(workspace_root="", package=CUR[-1] if CUR else "", name=s.lstrip(":")),
        "provider": lambda *a, **k: Anything(), "rule": lambda *a, **k: record_rule("custom_rule"),
        "macro": lambda *a, **k: record_rule("custom_macro"),
        "aspect": lambda *a, **k: Anything(), "attr": Anything(), "depset": Depset,
        "True": True, "False": False, "None": None, "print": lambda *a, **k: None,
        "exports_files": lambda *a, **k: None, "package": lambda *a, **k: None,
        "licenses": lambda *a, **k: None, "visibility": lambda *a, **k: None,
        "module_extension": lambda *a, **k: Anything(), "tag_class": lambda *a, **k: Anything(),
        "config_common": Anything(), "platform_common": Anything(), "DefaultInfo": Anything(),
        "OutputGroupInfo": Anything(), "CcInfo": Anything(), "json": Anything(),
    }
    for n in ["filegroup", "genrule", "config_setting", "alias", "cc_library", "cc_binary",
              "sh_binary", "py_binary", "test_suite", "platform", "constraint_setting",
              "constraint_value", "label_flag", "string_flag", "bool_flag"]:
        b[n] = record_rule(n)
    return b


def resolve_bzl(path, from_pkg):
    if path.startswith("@"):
        return None
    if path.startswith("//"):
        p, f = path[2:].split(":", 1)
    elif path.startswith(":"):
        p, f = from_pkg, path[1:]
    else:
        p, f = from_pkg, path
    if p.startswith(STUB_PREFIXES):
        return None
    d = fs_dir(p)
    return (p, os.path.join(d, f)) if d else ("?", None)


def load_bzl(path, from_pkg):
    r = resolve_bzl(path, from_pkg)
    if r is None:
        return StubModule()
    p, fname = r
    if fname is None or not os.path.exists(fname):
        ERRORS.append(f"load of missing file {path} (from //{from_pkg})")
        return StubModule()
    if fname in FILES:
        return FILES[fname]
    ns = dict(builtins_for(p))
    FILES[fname] = ns
    exec(compile(starlark_to_py(open(fname).read()), fname, "exec"), ns)
    return ns


class RuleStub:
    def __init__(self, name):
        self._f = record_rule(name)

    def __call__(self, *a, **k):
        return self._f(*a, **k)

    def __getattr__(self, k):
        return Anything()

    def __add__(self, o):
        return o

    def __radd__(self, o):
        return o

    def __iter__(self):
        return iter([])

    def __bool__(self):
        return False

    def __getitem__(self, k):
        return Anything()

    def format(self, *a, **k):
        return ""


class Paths:
    dirname = staticmethod(lambda p: p.rsplit("/", 1)[0] if "/" in p else "")
    basename = staticmethod(lambda p: p.rsplit("/", 1)[-1])
    join = staticmethod(lambda *a: "/".join(x.strip("/") for x in a if x))
    relativize = staticmethod(lambda p, s: p[len(s):].lstrip("/") if p.startswith(s) else p)
    split_extension = staticmethod(lambda p: (p.rsplit(".", 1)[0], "." + p.rsplit(".", 1)[1]) if "." in p.rsplit("/", 1)[-1] else (p, ""))
    normalize = staticmethod(lambda p: p)
    is_absolute = staticmethod(lambda p: p.startswith("/"))


class StubModule(dict):
    def get(self, k, d=None):
        if k == "paths":
            return Paths
        return RuleStub(k)


import ast


class _ListViews(ast.NodeTransformer):
    """Starlark's dict.keys()/values()/items() return lists."""
    def visit_Call(self, node):
        self.generic_visit(node)
        f = node.func
        if isinstance(f, ast.Attribute) and f.attr in ("keys", "values", "items") and not node.args:
            return ast.copy_location(ast.Call(func=ast.Name(id="list", ctx=ast.Load()), args=[node], keywords=[]), node)
        return node


def starlark_to_py(src):
    tree = _ListViews().visit(ast.parse(src))
    return ast.fix_missing_locations(tree)


def eval_package(pkg):
    if pkg in PACKAGES and PACKAGES[pkg].get("__evaluated__"):
        return True
    if pkg.startswith(STUB_PREFIXES):
        return True
    d = fs_dir(pkg)
    if d is None:
        ERRORS.append(f"package //{pkg} is not mapped in the layout")
        return False
    bfile = next((os.path.join(d, b) for b in ("BUILD.bazel", "BUILD") if os.path.exists(os.path.join(d, b))), None)
    if bfile is None:
        ERRORS.append(f"package //{pkg} has no BUILD file ({d})")
        return False
    PACKAGES.setdefault(pkg, {})["__evaluated__"] = True
    CUR.append(pkg)
    try:
        ns = dict(builtins_for(pkg))
        exec(compile(starlark_to_py(open(bfile).read()), bfile, "exec"), ns)
    except Fail as e:
        ERRORS.append(f"//{pkg}: fail(): {e}")
    except Exception as e:
        import traceback; ERRORS.append(f"//{pkg}: {type(e).__name__}: {e} :: " + " | ".join(l.strip() for l in traceback.format_exc().splitlines()[-6:-1]))
    finally:
        CUR.pop()
    return True


def target_exists(p, t):
    targets = PACKAGES.get(p, {})
    if t in targets:
        return True
    # outputs of rules declare "<rule>/<out>" file targets
    for name, info in targets.items():
        if name == "__evaluated__":
            continue
        outs = info["kw"].get("outs") or info["kw"].get("out")
        if isinstance(outs, str):
            outs = [outs]
        if isinstance(outs, (list, tuple)) and (t in outs or any(t == f"{name}/{o}" for o in outs)):
            return True
        if t.startswith(name + "/"):
            return True
    d = fs_dir(p)
    return bool(d) and os.path.exists(os.path.join(d, t))


def main():
    todo = list(sys.argv[2:])
    seen = set()
    while todo:
        pkg = todo.pop()
        if pkg in seen:
            continue
        seen.add(pkg)
        eval_package(pkg)
        for (rp, rt, attr, lab) in list(REFS):
            n = norm_label(lab, rp)
            if n and n[0] not in seen and not n[0].startswith(STUB_PREFIXES):
                todo.append(n[0])
    bad = []
    for (rp, rt, attr, lab) in REFS:
        n = norm_label(lab, rp)
        if not n or n[0].startswith(STUB_PREFIXES):
            continue
        if not target_exists(*n):
            bad.append(f"//{rp}:{rt} [{attr}] -> {lab}")
    report = {
        "packages": {p: sorted(k for k in v if k != "__evaluated__") for p, v in PACKAGES.items()},
        "errors": ERRORS,
        "unresolved": sorted(set(bad)),
    }
    json.dump(report, open(sys.argv[1] + ".report.json", "w"), indent=1)
    print(f"packages evaluated: {len(PACKAGES)}; errors: {len(ERRORS)}; unresolved labels: {len(set(bad))}")
    for e in ERRORS[:40]:
        print("  ERROR", e)
    for b in sorted(set(bad))[:60]:
        print("  UNRESOLVED", b)


if __name__ == "__main__":
    main()
