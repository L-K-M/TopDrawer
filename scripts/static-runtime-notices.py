#!/usr/bin/env python3
"""Detect statically linked toolchain runtimes in ELF files and check their notices ship.

  static-runtime-notices.py scan PATH... [--json]
  static-runtime-notices.py check PATH... --notices FILE [--notices FILE]...
                            [--allow ID=REASON]...
  static-runtime-notices.py sbom SDK_BUNDLE_OR_SBOM_JSON

Package managers never list what a toolchain links into a binary on its own:
the Rust standard library, Go runtime, Swift runtime and Foundation's ICU
(--static-swift-stdlib), or the libraries of Swift's static Linux SDK (musl,
musl-fts, curl, BoringSSL, zlib, libxml2, mimalloc ...). This script finds
them by signatures that survive stripping and, in "check" mode, fails unless
the shipped notices name each component (and, where the binary reveals it,
the exact version, such as ICU's data version icudtNNl). A toolchain bump
that adds a library or changes ICU then fails the build instead of shipping
stale notices.

PATH may be a file or a directory (a staged package tree); symlinks are
skipped. --allow ID=REASON skips one component with a recorded reason.
"sbom" prints the components that a Swift static Linux SDK declares in its
sbom.spdx.json, as a starting point for deb-copyright.py components.
Python 3.8+, standard library only.
"""

import argparse
import glob
import json
import mmap
import os
import re
import struct
import sys

# id, display name, detection regex (bytes), version group or None, notice
# requirement ("required", "optional": attribution waived by a runtime
# exception, "none": public domain), notice regexes that must all match,
# whether the version must appear next to the name in the notices.
COMPONENTS = [
    ("rust-std", "Rust standard library", rb"/rustc/([0-9a-f]{40})/library/(?:std|core|alloc)/", None,
     "required", [r"Copyright notices for The Rust Standard Library"], False),
    ("go-runtime", "Go runtime and standard library", rb"\xff Go buildinf:", None,
     "required", [r"The Go Authors"], False),
    ("swift-runtime", "Swift runtime and Foundation", rb"swift-corelibs-foundation|swift_retain", None,
     "optional", [r"Runtime Library Exception"], False),
    ("icu", "ICU", rb"icudt(\d+)[lb]", 1,
     "required", [r"UNICODE LICENSE V3|Unicode, Inc\."], True),
    ("musl", "musl libc", rb"MUSL_LOCPATH", None,
     "required", [r"Rich Felker"], False),
    # Foundation's FileManager uses fts; on musl that comes from musl-fts (counted only with musl).
    ("musl-fts", "musl-fts", rb"fts_(?:open|accpath)", None,
     "required", [r"musl-fts"], False),
    ("curl", "curl", rb"libcurl/(\d+\.\d+\.\d+)", 1,
     "required", [r"Daniel Stenberg"], True),
    ("boringssl", "BoringSSL", rb"BoringSSL", None,
     "required", [r"BoringSSL"], False),
    ("openssl", "OpenSSL", rb"OpenSSL (\d+\.\d+\.\d+[a-z]?) ", 1,
     "required", [r"OpenSSL"], False),
    ("zlib", "zlib", rb"(?:in|de)flate (\d+\.\d+(?:\.\d+)*) Copyright", 1,
     "required", [r"Jean-loup Gailly"], True),
    ("libxml2", "libxml2", rb"libxml2: |libxml %d using libxml %d", None,
     "required", [r"Daniel Veillard"], False),
    ("mimalloc", "mimalloc", rb"mimalloc: |MIMALLOC_", None,
     "required", [r"mimalloc|Daan Leijen"], False),
    ("libarchive", "libarchive", rb"libarchive (\d+\.\d+\.\d+)", 1,
     "required", [r"libarchive|Tim Kientzle"], False),
    ("libfuse", "libfuse", rb"FUSE library version", None,
     "required", [r"libfuse"], False),
    ("libunwind", "LLVM libunwind / libc++abi", rb"LIBUNWIND_PRINT_APIS|libc\+\+abi: ", None,
     "optional", [r"LLVM[- ]exception|LLVM Exceptions"], False),
    ("sqlite", "SQLite", rb"SQLite format 3", None, "none", [], False),
]

NAME_PATTERN = {"icu": r"\bICU\b", "curl": r"\bcurl\b", "zlib": r"\bzlib\b", "openssl": r"\bOpenSSL\b",
                "libarchive": r"\blibarchive\b"}


def elf_info(data):
    """(is_elf, static, needed sonames) from the program headers of an ELF image."""
    if len(data) < 64 or data[:4] != b"\x7fELF":
        return False, False, []
    is64, e = data[4] == 2, "<" if data[5] == 1 else ">"
    try:
        if is64:
            phoff = struct.unpack_from(e + "Q", data, 0x20)[0]
            phentsize, phnum = struct.unpack_from(e + "HH", data, 0x36)
        else:
            phoff = struct.unpack_from(e + "I", data, 0x1C)[0]
            phentsize, phnum = struct.unpack_from(e + "HH", data, 0x2A)
        loads, dynamic, interp = [], None, False
        for i in range(phnum):
            base = phoff + i * phentsize
            p_type = struct.unpack_from(e + "I", data, base)[0]
            if is64:
                p_offset, p_vaddr = struct.unpack_from(e + "QQ", data, base + 8)
                p_filesz = struct.unpack_from(e + "Q", data, base + 32)[0]
            else:
                p_offset, p_vaddr = struct.unpack_from(e + "II", data, base + 4)
                p_filesz = struct.unpack_from(e + "I", data, base + 16)[0]
            if p_type == 1:
                loads.append((p_vaddr, p_offset, p_filesz))
            elif p_type == 2:
                dynamic = (p_offset, p_filesz)
            elif p_type == 3:
                interp = True
        needed, strtab = [], None
        if dynamic:
            size = 16 if is64 else 8
            fmt = e + ("qQ" if is64 else "iI")
            entries = []
            for off in range(dynamic[0], dynamic[0] + dynamic[1], size):
                tag, val = struct.unpack_from(fmt, data, off)
                if tag == 0:
                    break
                entries.append((tag, val))
                if tag == 5:
                    strtab = val
            if strtab is not None:
                base_off = next((o + strtab - v for v, o, s in loads if v <= strtab < v + s), None)
                if base_off is not None:
                    for tag, val in entries:
                        if tag == 1:
                            end = data.find(b"\0", base_off + val)
                            needed.append(data[base_off + val:end].decode("ascii", "replace"))
        return True, not interp and not needed, needed
    except (struct.error, ValueError):
        return True, False, []


def elf_files(paths):
    for path in paths:
        if os.path.isfile(path) and not os.path.islink(path):
            yield path
        elif os.path.isdir(path):
            for dirpath, dirnames, filenames in os.walk(path):
                dirnames.sort()
                for name in sorted(filenames):
                    full = os.path.join(dirpath, name)
                    if os.path.isfile(full) and not os.path.islink(full):
                        yield full
        elif not os.path.exists(path):
            sys.exit(f"static-runtime-notices: error: no such path: {path}")


def scan(paths):
    """Return {path: [(id, name, version, requirement), ...]} for ELF files with matches."""
    results = {}
    for path in elf_files(paths):
        with open(path, "rb") as fh:
            if fh.read(4) != b"\x7fELF":
                continue
            fh.seek(0)
            if os.fstat(fh.fileno()).st_size == 0:
                continue
            data = mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ)
        try:
            _, static, needed = elf_info(data)
            found = []
            for cid, name, regex, group, requirement, _markers, _versioned in COMPONENTS:
                match = re.search(regex, data)
                if not match:
                    continue
                if cid == "musl-fts" and not any(f[0] == "musl" for f in found):
                    continue
                if cid == "swift-runtime" and any(n.startswith(("libswiftCore.so", "libFoundation.so")) for n in needed):
                    continue  # dynamically linked runtime: the system or package provides it
                version = match.group(group).decode() if group else None
                found.append((cid, name, version, requirement))
            if found:
                results[path] = {"static": static, "components": found}
        finally:
            data.close()
    return results


def check(paths, notice_files, allows):
    text = ""
    for path in notice_files:
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                text += fh.read() + "\n"
        except OSError as error:
            sys.exit(f"static-runtime-notices: error: cannot read notices {path}: {error}")
    if not text.strip():
        sys.exit("static-runtime-notices: error: the notices files are empty")
    allowed = {}
    for item in allows:
        cid, _, reason = item.partition("=")
        if not reason.strip():
            sys.exit(f"static-runtime-notices: error: --allow {item!r} needs ID=REASON")
        allowed[cid] = reason.strip()
    table = {c[0]: c for c in COMPONENTS}
    errors, warnings, ok = [], [], []
    results = scan(paths)
    for path, info in sorted(results.items()):
        for cid, name, version, requirement in info["components"]:
            if requirement == "none":
                continue
            if cid in allowed:
                ok.append(f"{path}: {name}: allowed ({allowed[cid]})")
                continue
            _, _, _, _, _, markers, versioned = table[cid]
            missing = [m for m in markers if not re.search(m, text, re.I)]
            if versioned and version:
                name_re = NAME_PATTERN.get(cid, re.escape(name))
                # ICU's binary reveals only the major data version (icudt74l), so "ICU 74.1" matches
                # "74"; the other captured versions are exact, so "zlib 1.3.1" must not match "1.3".
                tail = r"(?!\d)" if cid == "icu" else r"(?!\.?\d)"
                if not re.search(rf"{name_re}[^\n]{{0,80}}(?<![\d.]){re.escape(version)}{tail}", text, re.I):
                    missing.append(f"{name} {version} (the version linked into the binary)")
            label = f"{name} {version}" if version else name
            if missing:
                message = f"{path}: links {label}, but the notices lack: {', '.join(missing)}"
                (errors if requirement == "required" else warnings).append(message)
            else:
                ok.append(f"{path}: {label}: notice present")
    for line in ok:
        print(f"ok: {line}")
    for line in warnings:
        print(f"warning (attribution waived by a runtime exception, recommended): {line}", file=sys.stderr)
    for line in errors:
        print(f"error: {line}", file=sys.stderr)
    if errors:
        sys.exit(1)
    if not results:
        print("static-runtime-notices: no statically linked runtimes detected")


def sbom(path):
    candidates = [path] if path.endswith(".json") else glob.glob(os.path.join(path, "**", "sbom.spdx.json"), recursive=True)
    if not candidates:
        sys.exit(f"static-runtime-notices: error: no sbom.spdx.json under {path}")
    with open(candidates[0], encoding="utf-8") as fh:
        doc = json.load(fh)
    skeleton = []
    for package in doc.get("packages", []):
        name, version = package.get("name", ""), package.get("versionInfo", "")
        declared = package.get("licenseDeclared") or package.get("licenseConcluded") or ""
        print(f"{name}\t{version or '(no version)'}\t{declared}\t{package.get('downloadLocation', '')}")
        skeleton.append({"name": name, "version": version or "FILL-ME", "license": declared or "FILL-ME",
                         "copyright": ["FILL-ME"], "source_url": package.get("downloadLocation", ""),
                         "license_files": ["FILL-ME"], "embedded_in": ["usr/bin/FILL-ME"]})
    print("\n# deb-copyright.py components skeleton (verify each SPDX id against the upstream text; "
          "remove what the binary does not link; scan shows what it does):", file=sys.stderr)
    json.dump(skeleton, sys.stderr, indent=1)
    print(file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="mode", required=True)
    s = sub.add_parser("scan")
    s.add_argument("paths", nargs="+")
    s.add_argument("--json", action="store_true")
    c = sub.add_parser("check")
    c.add_argument("paths", nargs="+")
    c.add_argument("--notices", action="append", required=True)
    c.add_argument("--allow", action="append", default=[], metavar="ID=REASON")
    b = sub.add_parser("sbom")
    b.add_argument("path")
    args = parser.parse_args()
    if args.mode == "scan":
        results = scan(args.paths)
        if args.json:
            json.dump(results, sys.stdout, indent=1)
            print()
        if not results and not args.json:
            print("static-runtime-notices: no statically linked runtimes detected")
        for path, info in sorted(results.items()):
            if args.json:
                break
            kind = "static executable" if info["static"] else "dynamically linked"
            print(f"{path} ({kind})")
            for cid, name, version, requirement in info["components"]:
                print(f"  {cid:14} {name}{' ' + version if version else ''}  [{requirement}]")
    elif args.mode == "check":
        check(args.paths, args.notices, args.allow)
    else:
        sbom(args.path)


if __name__ == "__main__":
    main()
