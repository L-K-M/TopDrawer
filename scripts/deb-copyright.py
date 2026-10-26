#!/usr/bin/env python3
"""Generate or check a DEP-5 debian/copyright and Third-Party-Notices.txt.

  deb-copyright.py generate SPEC.json --copyright-out PATH [--notices-out PATH]
                   [--sources-out PATH] [--merge-notices FILE]...
  deb-copyright.py check COPYRIGHT [--no-common-licenses] [--require REGEX]...

SPEC.json lists the project's own code and every bundled third-party
component (see deb-copyright.example.json). Components either ship as their
own files in the package ("files": installed paths) or are statically linked
into a package binary ("embedded_in": installed paths). Statically linked
components have no files of their own, so they are declared in the binary's
paragraph: its License is the project's license "and" each embedded
component's, and its Comment names each component. Every license id gets a
standalone License paragraph with the full text, read from the files the spec
names; the script fails when a text is missing or empty, so a component can
never ship without its notice. A GPL/LGPL/MPL-style component without a
source_url is always an error (MPL-2.0 requires telling recipients where the
Source Code Form is). --sources-out writes SOURCES.txt with each component's
version and source_url (plus optional "sources" lines).

The copyright file uses SPDX ids as DEP-5 short names (AND/OR become and/or,
"X WITH Y-exception" becomes "X with Y exception") and never points to
/usr/share/common-licenses, because the same tree is repacked into Flatpaks
and AppImages, which do not have it. For the same reason it names the notices
file as "next to this file" rather than by a /usr path.

Paths in the spec are relative to the spec file. $VAR and ${VAR} are expanded
from the environment in license file paths, version, source_url, sources and
comment (for toolchain files and versions found at build time); an unset
variable is an error. Python 3.8+,
standard library only.
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

FORMAT = "https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/"
RULE = "=" * 72
TOKEN = re.compile(r"\(|\)|[A-Za-z0-9][A-Za-z0-9.+:-]*")
COPYLEFT = re.compile(r"\b(A?L?GPL|MPL|EPL|CDDL|CC-BY-SA|OSL)-")


def die(message):
    sys.exit(f"deb-copyright: error: {message}")


# ------------------------------------------------------------ SPDX handling

def parse_expression(expr, where):
    """Split an SPDX expression into (dep5 text, [license atoms]); atoms keep their WITH part."""
    tokens = TOKEN.findall(expr)
    if "".join(tokens).replace(" ", "") != expr.replace(" ", ""):
        die(f"{where}: cannot parse license expression {expr!r}")
    atoms, out, depth, expect_operand = [], [], 0, True
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        upper = tok.upper()
        if tok == "(":
            if not expect_operand:
                die(f"{where}: misplaced '(' in {expr!r}")
            depth += 1
            out.append("(")
        elif tok == ")":
            depth -= 1
            if depth < 0 or expect_operand:
                die(f"{where}: misplaced ')' in {expr!r}")
            out.append(")")
        elif upper in ("AND", "OR"):
            if expect_operand:
                die(f"{where}: misplaced {tok} in {expr!r}")
            out.append(upper.lower())
            expect_operand = True
            i += 1
            continue
        else:
            if not expect_operand:
                die(f"{where}: missing AND/OR before {tok!r} in {expr!r}")
            atom, dep5 = tok, tok
            if i + 1 < len(tokens) and tokens[i + 1].upper() == "WITH":
                if i + 2 >= len(tokens):
                    die(f"{where}: WITH without an exception in {expr!r}")
                exception = tokens[i + 2]
                atom = f"{tok} WITH {exception}"
                keyword = re.sub(r"-?exception-?", "-", exception, flags=re.I).strip("-") or exception
                dep5 = f"{tok} with {keyword} exception"
                i += 2
            atoms.append((atom, dep5))
            out.append(dep5)
            expect_operand = False
            i += 1
            continue
        i += 1
    if depth or expect_operand:
        die(f"{where}: incomplete license expression {expr!r}")
    text = " ".join(out).replace("( ", "(").replace(" )", ")")
    return text, atoms


def wrap_needed(dep5):
    return " or " in dep5 and not (dep5.startswith("(") and dep5.endswith(")"))


# ------------------------------------------------------------------ inputs

def expand(raw, where):
    """Expand $VAR/${VAR} from the environment; fail on unset variables."""
    expanded = os.path.expandvars(raw)
    unset = re.search(r"\$(\{[^}]*\}|[A-Za-z_][A-Za-z0-9_]*)", expanded)
    if unset:
        die(f"{where}: unset environment variable {unset.group(0)} in {raw!r}")
    return expanded


def resolve_path(base, raw, where):
    path = Path(expand(raw, where))
    return path if path.is_absolute() else base / path


def as_list(value, where, key):
    """Accept a string or a list of strings; anything else is an error."""
    if isinstance(value, str):
        return [value]
    if isinstance(value, list) and all(isinstance(v, str) for v in value):
        return value
    die(f"{where}: \"{key}\" must be a string or a list of strings")


def read_text(path, where):
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as error:
        die(f"{where}: cannot read license text {path}: {error}")
    if not text.strip():
        die(f"{where}: license text {path} is empty")
    if "FILL-ME" in text:
        die(f"{where}: {path} still contains FILL-ME")
    return text.replace("\r\n", "\n").strip("\n") + "\n"


def license_texts(component, atoms, base, where):
    """Map each atom to its list of (file name, text)."""
    files = component.get("license_files")
    inline = str(component.get("license_text", "")).strip()
    if inline:
        # Only for a LicenseRef-* summary of a large set (e.g. hundreds of crates) whose
        # verbatim texts ship in the notices file; real licenses always come from files.
        if files or len(atoms) != 1 or not atoms[0][0].startswith("LicenseRef-"):
            die(f"{where}: license_text is only allowed for a single LicenseRef-* license, without license_files")
        if not re.search(r"[\w.-]+\.(?:txt|html|md)\b", inline):
            die(f"{where}: license_text must name the shipped notices file (e.g. Third-Party-Notices.txt "
                f"next to this file)")
        return {atoms[0][0]: [("license_text", inline + "\n")]}
    if not files:
        die(f"{where}: needs license_files (the full license text, e.g. upstream's LICENSE)")
    if isinstance(files, list):
        mapping = {atom: files for atom, _ in atoms}
    elif isinstance(files, dict):
        unknown = set(files) - {atom for atom, _ in atoms}
        if unknown:
            die(f"{where}: license_files keys {sorted(unknown)} are not in its license expression")
        mapping = files
    else:
        die(f"{where}: license_files must be a list or an object")
    result = {}
    for atom, _ in atoms:
        if not mapping.get(atom):
            die(f"{where}: no license_files for {atom}")
        result[atom] = [(resolve_path(base, f, where).name, read_text(resolve_path(base, f, where), where))
                        for f in as_list(mapping[atom], where, "license_files")]
    return result


def load_spec(path):
    spec_path = Path(path).resolve()
    with open(spec_path, encoding="utf-8") as fh:
        spec = json.load(fh)
    base = spec_path.parent
    for key in ("package", "upstream_name", "own"):
        if key not in spec:
            die(f"{path}: missing \"{key}\"")
    own = spec["own"]
    if "pending" in own:
        if not str(own["pending"]).strip():
            die(f"{path}: own.pending needs a sentence explaining that no license is stated")
        own_info = {"pending": own["pending"].strip()}
    else:
        dep5, atoms = parse_expression(own.get("license", ""), "own")
        own_info = {"dep5": dep5, "spdx": own["license"], "copyright": as_list(own.get("copyright") or die("own: needs copyright"), "own", "copyright"),
                    "texts": license_texts(own, atoms, base, "own"), "atoms": atoms}
    components = []
    names = set()
    for raw in spec.get("components", []):
        where = f"component {raw.get('name', '?')!r}"
        for key in ("name", "license", "copyright"):
            if not raw.get(key):
                die(f"{where}: missing \"{key}\"")
        if raw["name"] in names:
            die(f"{where}: duplicate name")
        names.add(raw["name"])
        for key in ("files", "embedded_in"):
            if key in raw:
                raw[key] = as_list(raw[key], where, key)
        if bool(raw.get("files")) == bool(raw.get("embedded_in")):
            die(f"{where}: needs exactly one of \"files\" (own installed files) or \"embedded_in\" (binaries "
                f"that statically link it)")
        for key in ("version", "source_url", "comment"):
            if key in raw:
                raw[key] = expand(str(raw[key]), where)
        raw["sources"] = [expand(str(line), where) for line in raw.get("sources", [])]
        dep5, atoms = parse_expression(raw["license"], where)
        if COPYLEFT.search(raw["license"]) and not raw.get("source_url"):
            die(f"{where}: copyleft components need a source_url (exact version or tag), which the copyright "
                f"file and SOURCES.txt name")
        components.append({**raw, "dep5": dep5, "atoms": atoms,
                           "copyright": as_list(raw["copyright"], where, "copyright"),
                           "texts": license_texts(raw, atoms, base, where)})
    components.sort(key=lambda c: c["name"].lower())
    return spec, own_info, components


# ------------------------------------------------------------------ output

def field(name, lines):
    """A DEP-5 field whose value spans several lines."""
    lines = [line for line in lines if line is not None]
    out = f"{name}: {lines[0]}\n" if lines[0] else f"{name}:\n"
    for line in lines[1:]:
        out += f" {line}\n" if line.strip() else " .\n"
    return out


def body(text):
    return "".join(f" {line}\n" if line.strip() else " .\n" for line in text.rstrip("\n").split("\n"))


def label(component):
    return f"{component['name']} {component.get('version', '')}".strip()


def generate(spec, own, components, notices_path):
    paragraphs = []
    header = [f"Format: {FORMAT}\n", f"Upstream-Name: {spec['upstream_name']}\n"]
    if spec.get("upstream_contact"):
        header.append(f"Upstream-Contact: {spec['upstream_contact']}\n")
    if spec.get("source"):
        header.append(f"Source: {spec['source']}\n")
    comment = ["Files: paths are installed paths in this package. Components statically",
               "linked into a binary are declared in that binary's paragraph."]
    if notices_path:
        # Location-independent, so the deb, AppImage and Flatpak (/app) copies stay verbatim.
        where = notices_path if "/" in notices_path else f"{notices_path}, next to this file"
        comment.append(f"Full third-party notices: {where}")
    if "pending" in own:
        comment += ["", own["pending"]]
    header.append(field("Comment", comment))
    paragraphs.append("".join(header))

    if "pending" not in own:
        paragraphs.append(field("Files", ["*"]) + field("Copyright", own["copyright"]) + f"License: {own['dep5']}\n")

    by_binary = {}
    for comp in components:
        for binary in comp.get("embedded_in", []):
            by_binary.setdefault(binary.lstrip("/"), []).append(comp)
    for comp in components:
        if comp.get("files"):
            note = [f"{label(comp)}" + (f", {comp['source_url']}" if comp.get("source_url") else "")]
            if comp.get("comment"):
                note.append(comp["comment"])
            paragraphs.append(field("Files", [" ".join(f.lstrip("/") for f in comp["files"])])
                              + field("Copyright", comp["copyright"]) + f"License: {comp['dep5']}\n"
                              + field("Comment", note))
    for binary, comps in sorted(by_binary.items()):
        parts = [] if "pending" in own else [own["dep5"]]
        holders = [] if "pending" in own else list(own["copyright"])
        note = [f"{binary} statically links:"]
        for comp in comps:
            dep5 = f"({comp['dep5']})" if wrap_needed(comp["dep5"]) else comp["dep5"]
            if dep5 not in parts:
                parts.append(dep5)
            holders += [h for h in comp["copyright"] if h not in holders]
            line = f"- {label(comp)} ({comp['license']})"
            if comp.get("source_url"):
                line += f", {comp['source_url']}"
            note.append(line)
            if comp.get("comment"):
                note.append(f"  {comp['comment']}")
        paragraphs.append(field("Files", [binary]) + field("Copyright", holders)
                          + f"License: {' and '.join(parts)}\n" + field("Comment", note))

    texts = {}
    order = []
    items = ([("own", own)] if "pending" not in own else []) + [(label(c), c) for c in components]
    for name, item in items:
        for atom, dep5 in item["atoms"]:
            if dep5 not in texts:
                texts[dep5] = []
                order.append(dep5)
            for fname, text in item["texts"][atom]:
                if all(text != t for _, _, t in texts[dep5]):
                    texts[dep5].append((name, fname, text))
    own_dep5 = [] if "pending" in own else [d for _, d in own["atoms"]]
    for dep5 in own_dep5 + sorted((d for d in order if d not in own_dep5), key=str.lower):
        entries = texts[dep5]
        if len(entries) == 1:
            paragraphs.append(f"License: {dep5}\n" + body(entries[0][2]))
        else:
            combined = []
            for name, fname, text in entries:
                who = "this project" if name == "own" else name
                combined.append(f"Text as shipped by {who} ({fname}):\n\n{text}")
            paragraphs.append(f"License: {dep5}\n" + body("\n".join(combined)))
    return "\n".join(paragraphs)


def sources(spec, components):
    """SOURCES.txt: exact versions and source links (load_spec requires them for copyleft components)."""
    out = [f"Corresponding source for third-party components in {spec['upstream_name']} ({spec['package']})\n",
           f"{RULE}\n\n[copyleft] marks components under the GPL, LGPL, MPL or similar terms.\n"]
    for comp in components:
        if not comp.get("source_url"):
            continue
        flag = " [copyleft]" if COPYLEFT.search(comp["license"]) else ""
        out.append(f"\n{label(comp)} ({comp['license']}){flag}\n  Source: {comp['source_url']}\n")
        for line in comp.get("sources", []):
            out.append(f"  {line}\n")
    return "".join(out)


def notices(spec, own, components, merge):
    project = spec["upstream_name"]
    out = [f"Third-party notices for {project} ({spec['package']})\n\n"]
    if "pending" in own:
        out.append(f"{own['pending']}\n")
    else:
        out.append(f"{project}'s own code: {own['spdx']} (see the copyright file).\n")
    out.append("The components below keep their own licenses. Generated by deb-copyright.py.\n")
    for comp in components:
        out.append(f"\n{RULE}\n{label(comp)}\nLicense: {comp['license']}\n")
        if comp.get("source_url"):
            out.append(f"Source: {comp['source_url']}\n")
        out.append("Copyright: " + "\n           ".join(comp["copyright"]) + "\n")
        where = comp.get("files") or comp.get("embedded_in")
        how = "Files" if comp.get("files") else "Statically linked into"
        out.append(f"{how}: {' '.join(p.lstrip('/') for p in where)}\n")
        if comp.get("comment"):
            out.append(f"{comp['comment']}\n")
        seen = []
        for atom, _ in comp["atoms"]:
            for fname, text in comp["texts"][atom]:
                if text not in seen:
                    seen.append(text)
                    out.append(f"\n--- {fname} ---\n{text}")
    for path in merge:
        text = read_text(Path(path), "--merge-notices")
        out.append(f"\n{RULE}\n{text}")
    return "".join(out)


# ------------------------------------------------------------------- check

def parse_dep5(text):
    paragraphs = []
    for block in re.split(r"\n\s*\n", text.strip("\n")):
        fields, current = {}, None
        for line in block.split("\n"):
            if line.startswith((" ", "\t")):
                if current is None:
                    raise ValueError(f"continuation line before any field: {line!r}")
                fields[current].append(line[1:])
            elif ":" in line:
                current, value = line.split(":", 1)
                fields[current] = [value.strip()]
            elif line.strip():
                raise ValueError(f"not a field: {line!r}")
        paragraphs.append(fields)
    return paragraphs


def check(path, no_common, require):
    text = Path(path).read_text(encoding="utf-8")
    errors = []
    try:
        paragraphs = parse_dep5(text)
    except ValueError as error:
        die(f"{path}: {error}")
    if not paragraphs or "Format" not in paragraphs[0]:
        errors.append("first paragraph has no Format: field (not machine-readable DEP-5)")
    standalone = {p["License"][0]: p["License"][1:] for p in paragraphs if "License" in p and "Files" not in p
                  and "Format" not in p}
    files_paragraphs = [p for p in paragraphs if "Files" in p]
    if not files_paragraphs:
        errors.append("no Files paragraphs")
    for p in files_paragraphs:
        name = " ".join(p["Files"]).strip()
        for key in ("Copyright", "License"):
            if key not in p or not "".join(p[key]).strip():
                errors.append(f"Files: {name}: missing {key}")
        if "License" not in p:
            continue
        if any(line.strip() and line.strip() != "." for line in p["License"][1:]):
            continue  # text given inline
        expr = " ".join([p["License"][0]] + [l.strip() for l in p["License"][1:]])
        for atom in re.split(r"\s+(?:and|or)\s+|,\s*", expr.replace("(", " ").replace(")", " ")):
            atom = atom.strip()
            if not atom:
                continue
            body_lines = standalone.get(atom)
            if body_lines is None:
                errors.append(f"Files: {name}: license {atom!r} has no standalone License paragraph")
            elif not any(line.strip() and line.strip() != "." for line in body_lines):
                errors.append(f"License: {atom}: empty text")
    if no_common and "/usr/share/common-licenses" in text:
        errors.append("refers to /usr/share/common-licenses, which Flatpak runtimes and AppImage hosts lack; "
                      "include the full text")
    for regex in require:
        if not re.search(regex, text):
            errors.append(f"no match for required pattern /{regex}/")
    for error in errors:
        print(f"deb-copyright: {path}: {error}", file=sys.stderr)
    if errors:
        sys.exit(1)
    print(f"deb-copyright: {path}: ok ({len(files_paragraphs)} Files paragraphs, {len(standalone)} license texts)")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="mode", required=True)
    g = sub.add_parser("generate")
    g.add_argument("spec")
    g.add_argument("--copyright-out", required=True)
    g.add_argument("--notices-out")
    g.add_argument("--sources-out", help="write SOURCES.txt (exact versions and source links)")
    g.add_argument("--notices-name", default="Third-Party-Notices.txt",
                   help="notices file the header points to when another generator writes it: a file name "
                        "next to the copyright file, or an absolute path (jpackage's lib/app/resources/)")
    g.add_argument("--merge-notices", action="append", default=[],
                   help="append another generator's notices file (e.g. crate or wheel notices)")
    c = sub.add_parser("check")
    c.add_argument("copyright")
    c.add_argument("--no-common-licenses", action="store_true")
    c.add_argument("--require", action="append", default=[], metavar="REGEX")
    args = parser.parse_args()
    if args.mode == "check":
        check(args.copyright, args.no_common_licenses, args.require)
        return
    spec, own, components = load_spec(args.spec)
    notices_name = Path(args.notices_out).name if args.notices_out else args.notices_name
    copyright_text = generate(spec, own, components, notices_name)
    Path(args.copyright_out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.copyright_out).write_text(copyright_text, encoding="utf-8")
    if args.notices_out:
        Path(args.notices_out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.notices_out).write_text(notices(spec, own, components, args.merge_notices), encoding="utf-8")
    elif args.merge_notices:
        die("--merge-notices needs --notices-out")
    if args.sources_out:
        Path(args.sources_out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.sources_out).write_text(sources(spec, components), encoding="utf-8")
    print(f"deb-copyright: wrote {args.copyright_out}" + (f" and {args.notices_out}" if args.notices_out else "")
          + f" ({len(components)} components)")


if __name__ == "__main__":
    main()
