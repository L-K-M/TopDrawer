#!/usr/bin/env bash
# Cuts a release: bumps the version, commits, tags "v<version>", and with --push
# pushes branch + tag — which triggers .github/workflows/release.yml to build,
# package (.zip + .dmg, plus the Linux .deb), and publish the GitHub Release. A
# version with a pre-release suffix (2.2.0-beta.1) publishes a GitHub pre-release,
# which the in-app updater ignores. CI derives the released
# version from the tag, so the tag is the source of truth — this just keeps the
# committed MARKETING_VERSION and the README version line in step so *local/dev*
# builds (and the in-app updater) report the same number. The updater normalises
# a leading "v" and trailing ".0"s, so only the numbers have to match (tag "v1.3"
# == version "1.3.0").
#
#   scripts/release.sh 1.3.0          # bump MARKETING_VERSION + README, commit, tag v1.3.0
#   scripts/release.sh 1.3.0 --push   # …also push the commit + tag (CI then publishes)
#   scripts/release.sh                # tag the current MARKETING_VERSION as-is
#
# Usage: scripts/release.sh [X.Y[.Z]] [--push]
# Shared engine: https://github.com/L-K-M/release-tool (this stub only sets config).
set -euo pipefail

export RELEASE_APP_NAME="Top Drawer"
export RELEASE_KIND="xcode"
export RELEASE_XCODE_PROJECT="MacDring.xcodeproj"
export RELEASE_XCODE_SCHEME="MacDring"
export RELEASE_CI_NOTE="CI (release.yml) will now build, package (.zip + .dmg + Linux .deb), and publish the GitHub Release for the tag."
export RELEASE_INVOKED_AS="scripts/release.sh"

BIN="${LKM_RELEASE_BIN:-lkm-release}"
command -v "$BIN" >/dev/null 2>&1 || {
  echo "error: lkm-release not found — clone https://github.com/L-K-M/release-tool and run ./install.sh" >&2
  exit 1
}
exec "$BIN" "$@"
