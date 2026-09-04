#!/usr/bin/env bash
# Builds the Debian package for Top Drawer's Linux port (LP-30): `topdrawerd`, the
# `topdrawer-shell` layer-shell frontend, and the daemon's systemd user unit, as a
# plain dpkg-deb layout — no debhelper, no source package. The release workflow runs
# this inside the same swift:6.3-noble container Linux CI builds in, so the package
# is built against Ubuntu 24.04's glibc/GTK and installs on 24.04 and newer.
#
#   linux/packaging/build-deb.sh <version> [--output <file.deb>] [--skip-lintian]
#
# <version> is the release version as tagged, without the leading `v` — `2.2.0` or
# `2.2.0-beta.1`. It is stamped into `TopDrawerVersion.current` (what `--version` and
# the daemon's `Ping` report) before building and restored afterwards, so the git tag
# stays the single source of truth, as it is for the macOS MARKETING_VERSION. A semver
# pre-release suffix becomes a Debian `~` suffix (`2.2.0~beta.1`) so dpkg sorts it
# *before* the final `2.2.0`; the file name keeps the tag's spelling (`~` is unsafe in
# GitHub release asset names).
#
# What the package installs:
#   /usr/bin/topdrawerd, /usr/bin/topdrawer-shell   (release builds, Swift runtime linked
#                                                    statically — Ubuntu ships no Swift runtime)
#   /usr/lib/systemd/user/topdrawerd.service        (the committed unit, ExecStart → /usr/bin)
#   /usr/lib/topdrawer/libgtk4-layer-shell.so.0*    (a private copy, MIT — Ubuntu packages the
#                                                    GTK4 binding only from 25.10; the shell
#                                                    is linked with an rpath to this directory,
#                                                    so it runs on 24.04 too)
#   /usr/share/doc/topdrawer/{copyright,changelog.gz,README.md}
# Runtime `Depends` come from dpkg-shlibdeps (the exact shared-library packages the
# binaries load) plus the CLIs the daemon shells out to and a session bus.
#
# Environment:
#   TOPDRAWER_LAYER_SHELL_LIB      libgtk4-layer-shell.so.0 to vendor. Default: the one
#                                  pkg-config's gtk4-layer-shell-0 libdir provides.
#   TOPDRAWER_LAYER_SHELL_LICENSE  its MIT license text, reproduced in the copyright file.
#                                  Default: /usr/share/doc/gtk4-layer-shell/LICENSE (where
#                                  .github/actions/setup-gtk4-layer-shell puts it), then the
#                                  distro package's /usr/share/doc/libgtk4-layer-shell0/copyright.
#   TOPDRAWER_NO_VENDOR_LAYER_SHELL=1  depend on the distro's libgtk4-layer-shell0 instead
#                                  (Ubuntu 25.10+ only — the package then won't install on 24.04).
#   SOURCE_DATE_EPOCH              changelog timestamp (default: now).
set -euo pipefail
umask 022

usage() { sed -n '2,/^set -euo pipefail/{/^set -euo/!s/^# \{0,1\}//p}' "$0"; }

# MARK: - Arguments

version=""
output=""
run_lintian=1
while [ $# -gt 0 ]; do
  case "$1" in
    --output) [ $# -ge 2 ] || { echo "error: --output needs a path" >&2; exit 2; }
              output="$2"; shift 2 ;;
    --skip-lintian) run_lintian=0; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "error: unknown option $1" >&2; exit 2 ;;
    *) [ -z "$version" ] || { echo "error: unexpected argument $1" >&2; exit 2; }
       version="$1"; shift ;;
  esac
done
[ -n "$version" ] || { echo "error: a version is required, e.g. $0 2.2.0" >&2; usage >&2; exit 2; }
# major.minor[.patch][-prerelease]: what the release tags carry, and a shape both Debian
# (after the `-` → `~` swap below) and the app's SemanticVersion parser accept.
[[ "$version" =~ ^[0-9]+(\.[0-9]+){1,2}(-[0-9A-Za-z][0-9A-Za-z.]*)?$ ]] \
  || { echo "error: version '$version' is not X.Y[.Z][-prerelease]" >&2; exit 2; }
deb_version="${version//-/\~}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
pkg="$root/linux"
arch="$(dpkg --print-architecture)"
[ -n "$output" ] || output="$pkg/.build/deb/topdrawer_${deb_version}_${arch}.deb"
case "$output" in /*) ;; *) output="$PWD/$output" ;; esac

for tool in swift dpkg-deb dpkg-shlibdeps strip gzip install; do
  command -v "$tool" >/dev/null 2>&1 || { echo "error: $tool not found (need swift, dpkg-dev, binutils)" >&2; exit 1; }
done

vendor_layer_shell=1
[ "${TOPDRAWER_NO_VENDOR_LAYER_SHELL:-0}" = 1 ] && vendor_layer_shell=0
layer_shell_lib=""
layer_shell_license=""
if [ "$vendor_layer_shell" = 1 ]; then
  # Resolve the SONAME link to the real file; the package recreates the link itself.
  layer_shell_lib="${TOPDRAWER_LAYER_SHELL_LIB:-}"
  if [ -z "$layer_shell_lib" ]; then
    libdir="$(pkg-config --variable=libdir gtk4-layer-shell-0 2>/dev/null || true)"
    [ -n "$libdir" ] || { echo "error: pkg-config can't find gtk4-layer-shell-0; build it from source first (see linux/README.md) or set TOPDRAWER_LAYER_SHELL_LIB" >&2; exit 1; }
    layer_shell_lib="$libdir/libgtk4-layer-shell.so.0"
  fi
  layer_shell_lib="$(readlink -f "$layer_shell_lib")"
  [ -f "$layer_shell_lib" ] || { echo "error: no gtk4-layer-shell library at $layer_shell_lib" >&2; exit 1; }
  for candidate in "${TOPDRAWER_LAYER_SHELL_LICENSE:-}" /usr/share/doc/gtk4-layer-shell/LICENSE /usr/share/doc/libgtk4-layer-shell0/copyright; do
    [ -n "$candidate" ] && [ -f "$candidate" ] && { layer_shell_license="$candidate"; break; }
  done
  [ -n "$layer_shell_license" ] || { echo "error: gtk4-layer-shell's license text not found; set TOPDRAWER_LAYER_SHELL_LICENSE (vendoring MIT code requires shipping its notice)" >&2; exit 1; }
fi

# MARK: - Stamp the version

version_file="$pkg/Sources/TopDrawerVersion/TopDrawerVersion.swift"
version_backup="$(mktemp)"
cp "$version_file" "$version_backup"
restore_version() { cp "$version_backup" "$version_file"; rm -f "$version_backup"; }
trap restore_version EXIT
[ "$(grep -c '^    public static let current = "' "$version_file")" = 1 ] \
  || { echo "error: expected exactly one 'public static let current = \"…\"' line in $version_file" >&2; exit 1; }
sed -i "s|^\(    public static let current = \"\)[^\"]*\(\"\)|\1${version}\2|" "$version_file"
grep -q "^    public static let current = \"${version}\"$" "$version_file" \
  || { echo "error: version stamp failed" >&2; exit 1; }

# MARK: - Build

echo "==> Building topdrawerd + topdrawer-shell $version (release, static Swift runtime)"
# --disable-automatic-resolution: exactly the pinned Package.resolved, like CI.
# --static-swift-stdlib: no Swift runtime .so's to ship (Ubuntu has no such package).
# rpath /usr/lib/topdrawer: where the package puts its private gtk4-layer-shell copy;
# the loader checks it before the system directories, so a distro copy (25.10+) is
# never mixed in, and an absent private copy falls back to the distro's.
swift build -c release --package-path "$pkg" --disable-automatic-resolution --static-swift-stdlib \
  -Xlinker -rpath -Xlinker /usr/lib/topdrawer
bin_path="$(swift build -c release --package-path "$pkg" --show-bin-path)"
for exe in topdrawerd topdrawer-shell; do
  [ -x "$bin_path/$exe" ] || { echo "error: $bin_path/$exe was not built" >&2; exit 1; }
  # The build must report the stamped version, or the package would lie about itself.
  reported="$("$bin_path/$exe" --version)"
  [ "$reported" = "$exe $version" ] || { echo "error: $exe --version says '$reported', expected '$exe $version'" >&2; exit 1; }
done

# MARK: - Stage the package tree

stage="$(mktemp -d)"
chmod 755 "$stage"   # mktemp makes it 0700; it becomes the package's `./` entry
cleanup() { restore_version; rm -rf "$stage"; }
trap cleanup EXIT

install -Dm755 "$bin_path/topdrawerd" "$stage/usr/bin/topdrawerd"
install -Dm755 "$bin_path/topdrawer-shell" "$stage/usr/bin/topdrawer-shell"
# What dh_strip does for executables: drop symbols and the toolchain notes.
strip --strip-unneeded --remove-section=.comment --remove-section=.note "$stage/usr/bin/topdrawerd" "$stage/usr/bin/topdrawer-shell"

# The committed unit is written for the per-user install (ExecStart under ~/.local/bin);
# the package's copy runs the system-wide binary. A whole-line match, asserted, so an
# edit to the unit that moves ExecStart fails here instead of shipping a dead unit.
unit_src="$pkg/systemd/topdrawerd.service"
grep -q '^ExecStart=%h/.local/bin/topdrawerd$' "$unit_src" \
  || { echo "error: $unit_src no longer has the expected ExecStart line; update this script" >&2; exit 1; }
install -Dm644 /dev/null "$stage/usr/lib/systemd/user/topdrawerd.service"
sed 's|^ExecStart=%h/.local/bin/topdrawerd$|ExecStart=/usr/bin/topdrawerd|' "$unit_src" > "$stage/usr/lib/systemd/user/topdrawerd.service"

if [ "$vendor_layer_shell" = 1 ]; then
  real_name="$(basename "$layer_shell_lib")"
  install -Dm644 "$layer_shell_lib" "$stage/usr/lib/topdrawer/$real_name"
  strip --strip-unneeded --remove-section=.comment --remove-section=.note "$stage/usr/lib/topdrawer/$real_name"
  soname="$(objdump -p "$stage/usr/lib/topdrawer/$real_name" | awk '/SONAME/ {print $2}')"
  [ -n "$soname" ] || { echo "error: $real_name has no SONAME" >&2; exit 1; }
  [ "$soname" = "$real_name" ] || ln -s "$real_name" "$stage/usr/lib/topdrawer/$soname"
fi

# MARK: - Docs: copyright (DEP-5), changelog, README

docdir="$stage/usr/share/doc/topdrawer"
mkdir -p "$docdir"
indent() { sed 's/^/ /; s/^ $/ ./'; }   # DEP-5 continuation lines; blank lines become " ."
{
  cat <<HDR
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: Top Drawer
Upstream-Contact: https://github.com/L-K-M/TopDrawer
Source: https://github.com/L-K-M/TopDrawer

Files: *
Copyright: Top Drawer contributors
License: public-domain
HDR
  indent < "$root/LICENSE"
  cat <<'DEPS'

Files: debian/statically-linked-swift-packages
Comment:
 The executables statically link the Swift runtime and standard library and these
 SwiftPM packages (see linux/Package.resolved for the exact revisions): the Swift
 runtime, Foundation, swift-log, swift-nio (+ swift-nio-ssl, -extras, -http2),
 swift-collections, swift-atomics, swift-algorithms, swift-async-algorithms,
 swift-system, swift-numerics, swift-http-types, swift-http-structured-headers,
 swift-asn1, swift-certificates, swift-service-lifecycle — all Apache-2.0 (the
 Swift runtime with the runtime library exception); swift-crypto (Apache-2.0),
 which embeds BoringSSL (ISC / OpenSSL / others, see its LICENSE); and
 wendylabsinc/dbus (Apache-2.0).
Copyright: the respective authors
License: Apache-2.0
 On Debian systems, the full text of the Apache License 2.0 can be found in
 /usr/share/common-licenses/Apache-2.0.
DEPS
  if [ "$vendor_layer_shell" = 1 ]; then
    cat <<'LS'

Files: usr/lib/topdrawer/libgtk4-layer-shell.so.*
Comment:
 A private copy of gtk4-layer-shell (https://github.com/wmww/gtk4-layer-shell),
 shipped because Ubuntu packages the GTK4 binding only from 25.10.
Copyright: 2023 Sophie Winter
License: Expat
LS
    indent < "$layer_shell_license"
  fi
} > "$docdir/copyright"

# A "native" package (no separate upstream tarball), so the changelog is changelog.gz.
stamp="${SOURCE_DATE_EPOCH:-$(date +%s)}"
maintainer="Lukas (L-K-M) <5646645+L-K-M@users.noreply.github.com>"
{
  printf 'topdrawer (%s) unstable; urgency=medium\n\n' "$deb_version"
  printf '  * Top Drawer %s. Release notes:\n' "$version"
  printf '    https://github.com/L-K-M/TopDrawer/releases/tag/v%s\n\n' "$version"
  printf ' -- %s  %s\n' "$maintainer" "$(date -R -u -d "@$stamp")"
} | gzip -9n > "$docdir/changelog.gz"
install -m644 "$pkg/README.md" "$docdir/README.md"

# MARK: - control

# dpkg-shlibdeps wants a debian/control in the cwd naming the package; -O prints the
# computed field instead of writing substvars. It recognises "the package being
# built" by walking up from each file to a directory holding DEBIAN/ — so that
# directory must exist *before* it runs: the vendored gtk4-layer-shell then counts
# as shipped by this package (no dependency generated for it, only for what it
# itself links), and the executables' $ORIGIN rpath resolves. -l additionally
# points the library search at the private directory.
mkdir -p "$stage/DEBIAN"
shlibdeps_dir="$(mktemp -d)"
mkdir -p "$shlibdeps_dir/debian"
printf 'Source: topdrawer\n\nPackage: topdrawer\nArchitecture: any\n' > "$shlibdeps_dir/debian/control"
shlib_args=(-e"$stage/usr/bin/topdrawerd" -e"$stage/usr/bin/topdrawer-shell")
if [ "$vendor_layer_shell" = 1 ]; then
  shlib_args+=(-l"$stage/usr/lib/topdrawer" -e"$stage/usr/lib/topdrawer/$real_name")
fi
shlibs="$(cd "$shlibdeps_dir" && dpkg-shlibdeps -O "${shlib_args[@]}")"
rm -rf "$shlibdeps_dir"
shlibs="${shlibs#shlibs:Depends=}"
[ -n "$shlibs" ] || { echo "error: dpkg-shlibdeps produced no dependencies" >&2; exit 1; }

# Beyond the shared libraries: the daemon shells out to `gio` (launch / open / trash /
# mount) from libglib2.0-bin, and needs a session bus to claim its name on. udisksctl
# (eject) and xdg-open (launch fallback) are nice-to-have, so Recommends.
depends="$shlibs, libglib2.0-bin, default-dbus-session-bus | dbus-session-bus"
[ "$vendor_layer_shell" = 1 ] || depends="$depends, libgtk4-layer-shell0"

installed_size="$(du -sk --apparent-size "$stage" | cut -f1)"
cat > "$stage/DEBIAN/control" <<CTRL
Package: topdrawer
Version: $deb_version
Architecture: $arch
Maintainer: $maintainer
Installed-Size: $installed_size
Depends: $depends
Recommends: udisks2, xdg-utils
Section: utils
Priority: optional
Homepage: https://github.com/L-K-M/TopDrawer
Description: Top Drawer Linux daemon and layer-shell frontend (experimental)
 Top Drawer is a DragThing-style launcher: colored tabs anchored to the screen
 edges that expand into drawers of apps, files, folders and URLs.
 .
 This package contains the Linux port's background daemon (topdrawerd, a D-Bus
 session service serving the launcher document, mounted volumes, the Trash,
 recent files, launching and running-app state to the frontends) and the
 experimental gtk4-layer-shell frontend (topdrawer-shell) for compositors that
 implement wlr-layer-shell: KDE Plasma 6, sway, hyprland, COSMIC. On GNOME the
 daemon runs but the frontend exits by design (GNOME rejects layer-shell; its
 frontend is a planned Shell extension). Enable the daemon per user with
 'systemctl --user enable --now topdrawerd'.
CTRL
chmod 755 "$stage/DEBIAN"
chmod 644 "$stage/DEBIAN/control"

# MARK: - Build the .deb

mkdir -p "$(dirname "$output")"
dpkg-deb --build --root-owner-group "$stage" "$output"
echo "==> Built $output"
dpkg-deb --info "$output"
dpkg-deb --contents "$output"

if [ "$run_lintian" = 1 ]; then
  if command -v lintian >/dev/null 2>&1; then
    echo "==> lintian"
    # Fail on errors only; warnings/info are printed for the log. Expected, accepted
    # findings are suppressed by name with the reason recorded here:
    #   no-manual-page — the executables have --help; man pages are a follow-up.
    lintian --fail-on error --suppress-tags no-manual-page --info "$output" || exit 1
  else
    echo "note: lintian not installed — skipping (apt-get install lintian)" >&2
  fi
fi
