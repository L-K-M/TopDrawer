#!/usr/bin/env python3
"""Write Third-Party-Notices.txt for the Swift packages pinned in Package.resolved.

For every pin in one or more Package.resolved files (format v1, v2 or v3) this
finds the package checkout that Xcode or SwiftPM resolved, and concatenates its
license, copyright and NOTICE files verbatim under a header naming the
component, version, SPDX license and source URL. Extra components (vendored
code, prebuilt binaries, data tables, assets) come from an overrides file.

It fails, listing every problem, when a package has no license text, when its
license cannot be recognised, when the checkout is missing or at another
revision than the pin, when a package ships a prebuilt binary target nobody
has reviewed (per SwiftPM state or a .binaryTarget in its manifests), when an
MPL/GPL-family component lacks a source URL, or when an override is stale.
Gaps are closed with explicit overrides that must state a reason; nothing is
silently omitted.

Checkouts are found in this order: --checkouts; the SourcePackages/checkouts
directory above $BUILD_DIR (set in Xcode Run Script phases); .build/checkouts
next to the first Package.resolved (SwiftPM builds).

Python 3.9+ standard library only: Xcode build phases run the python3 that
ships with the Xcode command line tools.

Usage:
  swiftpm-notices.py [--resolved PATH ...] [--checkouts DIR] [--overrides FILE]
                     [--title TEXT] (--output FILE | --check FILE)
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import sys
from pathlib import Path

RULE = "=" * 78
FORMAT_VERSION = "1"

# File names that hold license, copyright or notice text, at the top level or
# nested (vendored code, fonts): LICENSE, COPYING.LIB, LICENSE-MIT, OFL.txt,
# GUST-FONT-LICENSE.txt, NOTICE, THIRD_PARTY_NOTICES.md, ...
LICENSE_WORD = re.compile(
    r"(^|[-_. ])(licen[cs]es?|copying|copyright|notices?|unlicense|ofl)([-_. ]|$)")
# Names that carry notices rather than a license; they need no SPDX match.
NOTICE_WORD = re.compile(r"(^|[-_. ])(notices?|copyright|authors)([-_. ]|$)")
TEXT_SUFFIXES = {"", ".txt", ".md", ".markdown", ".rst", ".html", ".htm", ".rtf"}
CODE_SUFFIXES = (
    ".swift", ".h", ".c", ".m", ".mm", ".cc", ".cpp", ".hpp", ".js", ".ts", ".py",
    ".json", ".plist", ".yml", ".yaml", ".rb", ".sh", ".png", ".jpg", ".svg", ".xib",
    ".storyboard", ".strings", ".metal", ".go", ".rs", ".java", ".kt", ".pbxproj",
    ".pdf", ".gz", ".zip", ".bz2", ".xz", ".tar", ".otf", ".ttf", ".woff", ".woff2",
    ".gif", ".icns", ".car", ".a", ".dylib", ".so", ".data", ".bin", ".dmg",
)
# Nested license files under these directories do not ship in an app. The
# broad list applies only to top-level directories of a package, so vendored
# code under e.g. Sources/CFoo/tools/ keeps its license.
SKIP_ANYWHERE = {".git", ".github", ".build", ".swiftpm", ".devcontainer",
                 "tests", "test", "fixtures"}
SKIP_TOP_LEVEL = SKIP_ANYWHERE | {
    "testing", "examples", "example", "demo", "demos", "benchmarks", "benchmark",
    "docs", "doc", "documentation", "scripts", "tools", "utils", "playgrounds",
}
SKIP_SUFFIXES = (".playground", ".xcodeproj", ".xcworkspace", ".docc")
# REUSE-style directories hold one license text per file (MIT.txt, ...).
LICENSE_DIRS = ("licenses", "licences")
BINARY_TARGET = re.compile(r"\.binaryTarget\s*\(\s*(?:name\s*:\s*\"([^\"]+)\")?")
# Licenses whose terms require telling recipients where the source is.
SOURCE_REQUIRED = re.compile(r"\b(MPL|GPL|LGPL|AGPL|EPL|CDDL|EUPL|CECILL)", re.I)

UNICODE = ["unicode license v3", "unicode, inc. license agreement"]
# Ordered (SPDX id, required phrases, forbidden phrases). Text is lowercased,
# whitespace-collapsed and quote-normalised before matching.
SIGNATURES = [
    ("curl", ["copyright and permission notice",
              "except as contained in this notice, the name of a copyright holder"], UNICODE),
    ("Apache-2.0", ["apache license", "version 2.0"], []),
    ("MIT", ["permission is hereby granted, free of charge, to any person obtaining a copy",
             "the above copyright notice and this permission notice shall be included"], []),
    ("MIT-0", ["permission is hereby granted, free of charge, to any person obtaining a copy"],
     ["the above copyright notice and this permission notice shall be included",
      "sil open font license", *UNICODE]),
    ("ISC", ["distribute this software for any purpose with or without fee is hereby granted",
             "provided that the above copyright notice and this permission notice appear"],
     ["copyright and permission notice"]),
    ("0BSD", ["distribute this software for any purpose with or without fee is hereby granted"],
     ["provided that the above copyright notice", "copyright and permission notice"]),
    ("BSD-4-Clause", ["redistribution and use in source and binary forms",
                      "all advertising materials mentioning"], ["openssl"]),
    ("BSD-3-Clause", ["redistribution and use in source and binary forms", "neither the name"],
     ["all advertising materials mentioning"]),
    ("BSD-2-Clause", ["redistribution and use in source and binary forms"],
     ["neither the name", "all advertising materials mentioning"]),
    ("Zlib", ["this software is provided 'as-is', without any express or implied warranty",
              "altered source versions must be plainly marked"], []),
    ("Unlicense", ["this is free and unencumbered software released into the public domain"], []),
    ("MPL-2.0", ["mozilla public license", "2.0"], []),
    ("BSL-1.0", ["boost software license - version 1.0"], []),
    ("CC0-1.0", ["cc0 1.0 universal"], []),
    ("OFL-1.1", ["sil open font license", "version 1.1"], []),
    ("Unicode-3.0", ["unicode license v3"], []),
    ("Unicode-DFS-2016", ["unicode, inc. license agreement - data files and software"],
     ["unicode license v3"]),
    ("OpenSSL", ["openssl license", "openssl project"], []),
]
EXCEPTIONS = [
    ("Swift-exception", "runtime library exception to the apache 2.0 license"),
    ("LLVM-exception", "llvm exceptions to the apache 2.0 license"),
]
# Phrases that turn several licenses in one text into alternatives (OR).
CHOICE = re.compile(r"at your option|dual[- ]licen[cs]ed|licensed under either|"
                    r"choose (either|one of)|you may choose")
# Copyleft texts need a human to pick -only/-or-later and check source-offer
# duties, so they are never classified automatically.
COPYLEFT = ["gnu general public license", "gnu lesser general public license",
            "gnu library general public license", "gnu affero general public license",
            "eclipse public license", "common development and distribution license"]

PACKAGE_KEYS = {"exclude", "license", "add_files", "skip_files", "binary_reviewed", "reason"}
COMPONENT_KEYS = {"name", "version", "license", "source", "files", "reason", "verify_version",
                  "sbom_name"}
SBOM_KEYS = {"file", "skip", "reason"}
TOP_KEYS = {"preamble", "packages", "components", "spdx_sbom", "comment"}


class Problems(Exception):
    pass


class Pin:
    def __init__(self, identity, location, state, kind):
        self.identity = identity.lower()
        self.location = location
        self.kind = kind
        self.version = state.get("version")
        self.branch = state.get("branch")
        self.revision = state.get("revision")
        base = location.rstrip("/").rsplit("/", 1)[-1]
        self.name = base[:-4] if base.endswith(".git") else base or identity

    def version_text(self):
        if self.version:
            return self.version
        if self.branch:
            return f"{self.branch} branch, revision {(self.revision or 'unknown')[:12]}"
        return f"revision {(self.revision or 'unknown')[:12]}"

    def source_text(self):
        if self.kind == "registry":
            return f"Swift package registry: {self.location}"
        # Drop user:token@ so credentials in a package URL never reach the
        # shipped file.
        url = re.sub(r"^([a-z][a-z0-9+.-]*://)[^/@]*@", r"\1", self.location, flags=re.I)
        url = url[:-4] if url.endswith(".git") else url
        return f"{url} (revision {self.revision})" if self.revision else url


def identity_from_url(url):
    base = url.rstrip("/").rsplit("/", 1)[-1]
    return (base[:-4] if base.endswith(".git") else base).lower()


def load_pins(paths, problems):
    pins = {}
    for path in paths:
        try:
            data = json.loads(Path(path).read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            problems.append(f"cannot read {path}: {error}")
            continue
        # A file in an unknown format must not pass as "no dependencies".
        version = data.get("version") if isinstance(data, dict) else None
        pins_list = (data.get("object") or {}).get("pins") if version == 1 else \
            data.get("pins") if version in (2, 3) else None
        if not isinstance(pins_list, list):
            problems.append(f"{path}: not a Package.resolved file of version 1, 2 or 3 "
                            "with a pins list")
            continue
        if version == 1:
            entries = [Pin(identity_from_url(p["repositoryURL"]), p["repositoryURL"],
                           p.get("state", {}), "remoteSourceControl")
                       for p in pins_list]
        else:
            entries = [Pin(p["identity"], p.get("location", ""), p.get("state", {}),
                           p.get("kind", "remoteSourceControl"))
                       for p in pins_list]
        for pin in entries:
            known = pins.get(pin.identity)
            if known and (known.revision, known.version) != (pin.revision, pin.version):
                problems.append(f"{pin.identity} is pinned to {known.version_text()} and "
                                f"{pin.version_text()} in different Package.resolved files")
            pins.setdefault(pin.identity, pin)
    return pins


def find_checkouts(explicit, resolved):
    if explicit:
        path = Path(explicit)
        return path / "checkouts" if (path / "checkouts").is_dir() else path
    build_dir = os.environ.get("BUILD_DIR")
    if build_dir:
        for parent in [Path(build_dir), *Path(build_dir).parents]:
            if (parent / "SourcePackages" / "checkouts").is_dir():
                return parent / "SourcePackages" / "checkouts"
    candidate = Path(resolved[0]).resolve().parent / ".build" / "checkouts"
    if candidate.is_dir():
        return candidate
    raise Problems(["no package checkouts found: resolve packages first "
                    "(xcodebuild -resolvePackageDependencies -clonedSourcePackagesDirPath DIR, "
                    "or swift package resolve) and pass --checkouts DIR"])


def workspace_state(checkouts):
    """Map identity -> (subpath, revision, {binary target: kind}) from SwiftPM state."""
    path = checkouts.parent / "workspace-state.json"
    if not path.is_file():
        return {}
    data = json.loads(path.read_text(encoding="utf-8")).get("object", {})
    state = {}
    for dependency in data.get("dependencies", []):
        identity = dependency["packageRef"]["identity"].lower()
        checkout = dependency.get("state", {}).get("checkoutState", {})
        state[identity] = [dependency.get("subpath"), checkout.get("revision"), {}]
    for artifact in data.get("artifacts", []):
        identity = artifact["packageRef"]["identity"].lower()
        state.setdefault(identity, [None, None, {}])[2][str(artifact.get("targetName"))] = \
            artifact.get("kind", "binary")
    return state


def binary_targets(name, root, state_targets, problems):
    """Binary targets from SwiftPM state plus the checkout's manifests. State
    alone misses artifacts SwiftPM could not fetch or unpack (Linux has no
    unzip in many images), so a .binaryTarget in any Package*.swift counts
    too, even if commented out: a false alarm costs one reviewed override."""
    targets = dict(state_targets)
    manifests = sorted(root.glob("Package@swift-*.swift")) + [root / "Package.swift"]
    if not manifests[-1].is_file():
        problems.append(f"{name}: no Package.swift in {root}; cannot check for binary targets")
        return targets
    for manifest in manifests:
        for match in BINARY_TARGET.finditer(read_text(manifest)):
            targets.setdefault(match.group(1) or "unnamed", f"in {manifest.name}")
    return targets


def checkout_head(root):
    """HEAD revision of a checkout whose .git is a directory or a gitdir file."""
    git = root / ".git"
    if git.is_file():
        match = re.match(r"gitdir:\s*(.+)", read_text(git))
        git = (root / match.group(1).strip()) if match else git
    head = git / "HEAD"
    text = read_text(head).strip() if head.is_file() else ""
    return text if re.fullmatch(r"[0-9a-f]{40}", text) else None


def locate(pin, checkouts, state, problems):
    subpath, revision, _ = state.get(pin.identity, [None, None, {}])
    candidates = [subpath] if subpath else []
    if pin.kind == "registry" and pin.version:
        scope, _, name = pin.identity.partition(".")
        candidates.append(f"../registry/downloads/{scope}/{name}/{pin.version}")
    names = {entry.name.lower(): entry.name for entry in checkouts.iterdir()} \
        if checkouts.is_dir() else {}
    candidates += [names[n.lower()] for n in (pin.name, pin.identity) if n.lower() in names]
    root = next((checkouts / c for c in candidates if (checkouts / c).is_dir()), None)
    if root is None:
        problems.append(f"{pin.name}: no checkout under {checkouts}; resolve packages first")
        return None
    revision = revision or checkout_head(root)
    if pin.revision and revision and revision != pin.revision:
        problems.append(f"{pin.name}: checkout is at {revision[:12]} but Package.resolved pins "
                        f"{pin.revision[:12]}; resolve packages again")
    return root


def is_license_name(name):
    lower = name.lower()
    stem, dot, suffix = lower.rpartition(".")
    if not dot or "." + suffix not in TEXT_SUFFIXES:
        if lower.endswith(CODE_SUFFIXES):
            return False
        stem = lower
    return bool(LICENSE_WORD.search(stem))


def license_files(root):
    found = []
    for directory, subdirs, files in os.walk(root):
        relative = Path(directory).relative_to(root)
        skip = SKIP_TOP_LEVEL if not relative.parts else SKIP_ANYWHERE
        subdirs[:] = sorted(d for d in subdirs if d.lower() not in skip
                            and not d.lower().endswith(SKIP_SUFFIXES))
        # Every text in a licenses/ directory counts, at any depth (vendored
        # code with its own REUSE layout), except code and data files.
        in_licenses_dir = any(part.lower() in LICENSE_DIRS for part in relative.parts)
        for name in files:
            listed = in_licenses_dir and not name.lower().endswith(CODE_SUFFIXES)
            if (listed or is_license_name(name)) and is_text(Path(directory) / name):
                found.append(relative / name)
    return sorted(found, key=lambda p: (len(p.parts), str(p).lower()))


def is_top_level(path):
    """Top-level texts (and the root licenses/ directory) cover the whole
    package and may be alternatives; deeper ones cover vendored parts."""
    return len(path.parts) == 1 or path.parts[0].lower() in LICENSE_DIRS


def is_text(path):
    """License files are text; skip binaries (PDFs, archives) with such names."""
    return b"\0" not in path.read_bytes()[:8192]


def read_text(path):
    data = Path(path).read_bytes()
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError:
        text = data.decode("latin-1")
    return text.replace("\r\n", "\n").replace("\r", "\n").strip("\n")


def detect(text):
    # Drop comment decoration (" * ", "//", "#") so headers copied from source
    # files match too, then collapse whitespace.
    lines = (re.sub(r"^\s*(/\*+|\*+/|\*+|//+|#+|--)?", "", line) for line in text.split("\n"))
    flat = " ".join(" ".join(lines).lower().split())
    flat = flat.replace("\u2018", "'").replace("\u2019", "'").replace("`", "'")
    flat = flat.replace("\u201c", '"').replace("\u201d", '"')
    if any(phrase in flat for phrase in COPYLEFT):
        return ["COPYLEFT"]
    found = []
    for spdx, required, forbidden in SIGNATURES:
        if all(p in flat for p in required) and not any(p in flat for p in forbidden):
            if spdx == "Apache-2.0":
                for exception, phrase in EXCEPTIONS:
                    if phrase in flat:
                        spdx = f"Apache-2.0 WITH {exception}"
            found.append(spdx)
    return found


def combine(ids):
    unique = list(dict.fromkeys(ids))
    if len(unique) <= 1:
        return unique[0] if unique else None
    return " AND ".join(f"({i})" if " WITH " in i else i for i in unique)


def load_overrides(path, pins, problems):
    if not path:
        return {"preamble": [], "packages": {}, "components": [], "spdx_sbom": None}, None
    base = Path(path).resolve().parent
    data = json.loads(Path(path).read_text(encoding="utf-8"))

    def text(value):
        return isinstance(value, str) and bool(value.strip())

    def strings(value):
        return isinstance(value, list) and all(text(item) for item in value)

    if not isinstance(data, dict):
        raise Problems([f"{path}: top level must be an object"])
    for key in set(data) - TOP_KEYS:
        problems.append(f"{path}: unknown key {key!r}")
    if not isinstance(data.get("preamble", []), list) or \
            not all(isinstance(line, str) for line in data.get("preamble", [])):
        problems.append(f"{path}: preamble must be a list of strings")
    packages = data.get("packages", {})
    components = data.get("components", [])
    sbom = data.get("spdx_sbom")
    if not isinstance(packages, dict) or not isinstance(components, list) or \
            not isinstance(sbom, (dict, type(None))):
        raise Problems([f"{path}: packages must be an object, components a list, "
                        "spdx_sbom an object"])
    for identity, entry in packages.items():
        where = f"{path}: packages.{identity}"
        if not isinstance(entry, dict):
            problems.append(f"{where}: must be an object")
            continue
        if identity not in pins:
            problems.append(f"{where}: not pinned in Package.resolved (stale override)")
        if not text(entry.get("reason")):
            problems.append(f"{where}: every override needs a non-empty \"reason\"")
        for key in set(entry) - PACKAGE_KEYS:
            problems.append(f"{where}: unknown key {key!r}")
        for key in ("add_files", "skip_files"):
            if key in entry and not strings(entry[key]):
                problems.append(f"{where}: {key} must be a list of paths")
        if "license" in entry and not text(entry["license"]):
            problems.append(f"{where}: license must be an SPDX expression")
    for index, entry in enumerate(components):
        where = f"{path}: components[{index}]"
        if not isinstance(entry, dict):
            problems.append(f"{where}: must be an object")
            continue
        for key in ("name", "version", "license", "reason"):
            if not text(entry.get(key)):
                problems.append(f"{where}: missing {key!r}")
        if not strings(entry.get("files")) or not entry.get("files"):
            problems.append(f"{where}: files must be a non-empty list of paths")
        if "verify_version" in entry and not (isinstance(entry["verify_version"], dict)
                                              and text(entry["verify_version"].get("file"))
                                              and text(entry["verify_version"].get("regex"))):
            problems.append(f"{where}: verify_version needs \"file\" and \"regex\"")
        for key in set(entry) - COMPONENT_KEYS:
            problems.append(f"{where}: unknown key {key!r}")
    if sbom is not None:
        for key in set(sbom) - SBOM_KEYS:
            problems.append(f"{path}: spdx_sbom: unknown key {key!r}")
        if not text(sbom.get("file")) or not text(sbom.get("reason")):
            problems.append(f"{path}: spdx_sbom needs \"file\" and \"reason\"")
        skip = sbom.get("skip", {})
        if not isinstance(skip, dict) or not all(text(r) for r in skip.values()):
            problems.append(f"{path}: spdx_sbom.skip maps names to reasons")
    return {"preamble": data.get("preamble", []), "packages": packages,
            "components": components, "spdx_sbom": sbom}, base


def check_sbom(overrides, base, problems):
    """Every package in a toolchain SBOM (SPDX JSON) must be a component with
    the same version, or be skipped with a reason, so SDK updates fail loudly."""
    sbom = overrides.get("spdx_sbom")
    if not sbom:
        return
    path = resolve_file(sbom["file"], base, {}, problems, "spdx_sbom", "SBOM")
    if path is None:
        return
    listed = {p["name"]: p.get("versionInfo") for p in json.loads(read_text(path))["packages"]}
    by_name = {c["sbom_name"]: c for c in overrides["components"] if c.get("sbom_name")}
    for name, version in sorted(listed.items()):
        if name in sbom.get("skip", {}):
            continue
        component = by_name.get(name)
        if component is None:
            problems.append(f"SBOM {sbom['file']} lists {name} {version} with no component "
                            "(add its license text, or skip it with a reason)")
        elif component["version"] != version:
            problems.append(f"component {component['name']} is {component['version']} but the "
                            f"SBOM lists {name} {version}; update the component and its texts")
    for name in sorted(set(by_name) - set(listed)):
        problems.append(f"component sbom_name {name!r} is not in the SBOM (stale override)")
    for name in sorted(set(sbom.get("skip", {})) - set(listed)):
        problems.append(f"spdx_sbom.skip {name!r} is not in the SBOM (stale override)")


def resolve_file(reference, base, roots, problems, where, kind="license file"):
    """Overrides-relative or absolute path ($VARS and ~ expand), or
    checkout:<identity>/<path> inside a resolved package."""
    if reference.startswith("checkout:"):
        identity, _, rest = reference[len("checkout:"):].partition("/")
        root = roots.get(identity.lower())
        if root is None:
            problems.append(f"{where}: {reference!r}: {identity!r} is not a located, "
                            "non-excluded pin")
            return None
        path = root / rest
    else:
        path = base / os.path.expanduser(os.path.expandvars(reference))
    if not path.is_file() or not read_text(path).strip():
        problems.append(f"{where}: {kind} {reference!r} is missing or empty")
        return None
    return path


def verify_version(component, base, roots, problems):
    """Fail when a pinned upstream file reports another version than the
    component entry, e.g. a prebuilt library's version header."""
    check = component.get("verify_version")
    if not check:
        return
    where = f"component {component['name']} verify_version"
    path = resolve_file(check.get("file", ""), base, roots, problems, where, "file")
    if path is None:
        return
    match = re.search(check.get("regex", "(?!)"), read_text(path), re.MULTILINE)
    found = match.group(1) if match and match.groups() else None
    # "expect" ties a component to another version, e.g. ICU to the Swift release.
    expected = check.get("expect", component["version"])
    if found != expected:
        problems.append(f"{where}: {check['file']} reports {found!r}, expected "
                        f"{expected!r}; update the component and its texts")


def entry_text(name, version, license_id, source, texts):
    lines = [RULE, f"{name} {version}", f"License: {license_id}"]
    if source:
        lines.append(f"Source: {source}")
    for label, text in texts:
        lines += ["", f"--- {label} ---", "", text]
    return "\n".join(lines) + "\n"


def build(args):
    problems = []
    pins = load_pins(args.resolved, problems)
    overrides, base = load_overrides(args.overrides, pins, problems)
    if problems:
        raise Problems(problems)
    if not pins and not overrides["components"]:
        raise Problems(["nothing to do: pass --resolved or an overrides file with components"])
    checkouts = find_checkouts(args.checkouts, args.resolved) if pins else Path()
    state = workspace_state(checkouts) if pins else {}
    entries, roots, summary = [], {}, []

    # Locate every included checkout first, so checkout: references in any
    # override resolve regardless of pin order.
    for identity in sorted(pins):
        if overrides["packages"].get(identity, {}).get("exclude"):
            continue
        root = locate(pins[identity], checkouts, state, problems)
        if root is not None:
            roots[identity] = root

    for identity in sorted(pins):
        pin, override = pins[identity], overrides["packages"].get(identity, {})
        if override.get("exclude"):
            summary.append(f"note: {pin.name}: excluded ({override['reason']})")
            continue
        root = roots.get(identity)
        if root is None:
            continue
        binaries = binary_targets(pin.name, root, state.get(identity, [None, None, {}])[2],
                                  problems)
        if binaries and not override.get("binary_reviewed"):
            listed = ", ".join(f"{name} ({kind})" for name, kind in sorted(binaries.items()))
            problems.append(f"{pin.name}: ships prebuilt binary targets {listed}; "
                            "add the binary's own license as a component and set "
                            "\"binary_reviewed\": true with a reason")
        skip = set(override.get("skip_files", []))
        found = license_files(root)
        for missing in sorted(skip - {str(f) for f in found}):
            problems.append(f"{pin.name}: skip_files entry {missing!r} is not a license file "
                            "the generator collects (missing, or under a skipped directory); "
                            "paths are relative to the checkout")
        # (label, text, role): top-level files may be alternatives (dual
        # licensing); nested and added files cover vendored parts.
        texts = [(str(f), read_text(root / f), "top" if is_top_level(f) else "nested")
                 for f in found if str(f) not in skip]
        for reference in override.get("add_files", []):
            path = resolve_file(reference, base, roots, problems, f"{pin.name} add_files")
            if path:
                texts.append((Path(reference).name, read_text(path), "added"))
        texts = [entry for entry in texts if entry[1].strip()]
        labels = ", ".join(label for label, _, _ in texts)
        if not texts:
            problems.append(f"{pin.name} {pin.version_text()}: no license text in {root}; "
                            "add the upstream text with an add_files override")
            continue
        license_id = override.get("license")
        if not license_id:
            detected = [(role, detect(text)) for _, text, role in texts]
            if any("COPYLEFT" in ids for _, ids in detected):
                problems.append(f"{pin.name}: copyleft license text found; set \"license\" "
                                "explicitly and follow the recipe's copyleft rules")
                continue
            top = {tuple(ids) for role, ids in detected if role == "top" and ids}
            if len(top) > 1:
                problems.append(f"{pin.name}: several top-level license files ({labels}); "
                                "set \"license\" to the right SPDX expression (AND or OR)")
                continue
            # One text offering a choice ("at your option", "dual licensed")
            # must not be reported as AND.
            choice = [label for (label, text, _), (_, ids) in zip(texts, detected)
                      if len(ids) > 1 and CHOICE.search(" ".join(text.lower().split()))]
            if choice:
                problems.append(f"{pin.name}: {', '.join(choice)} offers a choice of licenses; "
                                "set \"license\" to the right SPDX expression")
                continue
            unknown = [label for (label, _, role), (_, ids) in zip(texts, detected)
                       if not ids and not NOTICE_WORD.search(Path(label).name.lower())]
            if unknown:
                problems.append(f"{pin.name}: no SPDX id recognised in {', '.join(unknown)}; "
                                "set \"license\" to the full expression for all its texts")
                continue
            license_id = combine([i for _, ids in detected for i in ids])
            if not license_id:
                problems.append(f"{pin.name}: license not recognised in {labels}; "
                                "set \"license\"")
                continue
        texts = [(label, text) for label, text, _ in texts]
        entries.append(((pin.name.lower(), pin.version_text()),
                        entry_text(pin.name, pin.version_text(), license_id,
                                   pin.source_text(), texts)))
        summary.append(f"note: {pin.name} {pin.version_text()}: {license_id} ({labels})")

    check_sbom(overrides, base, problems)
    for component in overrides["components"]:
        where = f"component {component.get('name')}"
        if SOURCE_REQUIRED.search(component["license"]) and not component.get("source"):
            problems.append(f"{where}: {component['license']} requires telling recipients "
                            "where the source is; set \"source\" to the exact repository "
                            "or archive URL and version")
        verify_version(component, base, roots, problems)
        texts = []
        for reference in component.get("files", []):
            path = resolve_file(reference, base, roots, problems, where)
            if path:
                texts.append((Path(reference).name, read_text(path)))
        if texts:
            entries.append(((component["name"].lower(), component["version"]),
                            entry_text(component["name"], component["version"],
                                       component["license"], component.get("source"), texts)))
            summary.append(f"note: {component['name']} {component['version']}: "
                           f"{component['license']} (override: {component['reason']})")
    if problems:
        raise Problems(problems)
    if not entries:
        raise Problems(["no components: nothing to write (check Package.resolved and overrides)"])

    entries.sort(key=lambda item: item[0])
    heading = f"Third-party notices for {args.title}" if args.title else "Third-party notices"
    header = [heading, "", *overrides["preamble"]]
    if overrides["preamble"]:
        header.append("")
    header += ["Components:"]
    header += ["  " + body.split("\n")[1] + " (" + body.split("\n")[2][len("License: "):] + ")"
               for _, body in entries]
    header += ["", f"Generated by swiftpm-notices.py (format {FORMAT_VERSION}) from Package.resolved,",
               "the package checkouts and the listed overrides. Do not edit by hand.", ""]
    return "\n".join(header) + "\n" + "\n".join(body for _, body in entries), summary


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--resolved", action="append", default=[],
                        help="Package.resolved file (repeatable; omit for components only)")
    parser.add_argument("--checkouts", help="SourcePackages, SourcePackages/checkouts "
                                            "or .build/checkouts directory")
    parser.add_argument("--overrides", help="JSON overrides (see the recipe)")
    parser.add_argument("--title", help="product name for the heading")
    parser.add_argument("--quiet", action="store_true", help="do not list components")
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--output", help="file to write")
    target.add_argument("--check", help="committed file that must match the generated text")
    args = parser.parse_args()
    try:
        text, summary = build(args)
    except Problems as error:
        for problem in error.args[0]:
            print(f"error: {problem}", file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        print(f"error: {type(error).__name__}: {error}", file=sys.stderr)
        return 1
    if not args.quiet:
        print("\n".join(summary), file=sys.stderr)
    if args.check:
        current = Path(args.check).read_text(encoding="utf-8") if Path(args.check).is_file() else ""
        if current != text:
            diff = difflib.unified_diff(current.splitlines(), text.splitlines(),
                                        args.check, "generated", lineterm="", n=1)
            print("\n".join(list(diff)[:80]), file=sys.stderr)
            print(f"error: {args.check} is out of date; regenerate it with --output",
                  file=sys.stderr)
            return 1
        return 0
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
