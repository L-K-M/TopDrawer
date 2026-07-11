#!/usr/bin/env bash
# Builds "Top Drawer.app" from the command line and reveals it in Finder on success.
# Incremental Release build by default; --clean resets the wedged Swift Build service
# (the CreateBuildDescription / clang-probe hang) and wipes build/ before building.
# Thin stub for the shared lkm-build engine.
#
# Usage: scripts/build.sh [--clean] [--debug] [--run] [--install] [--zip] [--dmg]
# Shared engine: https://github.com/L-K-M/release-tool (this stub only sets config).
set -euo pipefail
export BUILD_APP_NAME="Top Drawer"
export BUILD_KIND="xcode"
export BUILD_XCODE_PROJECT="MacDring.xcodeproj"
export BUILD_XCODE_SCHEME="MacDring"
export BUILD_INVOKED_AS="scripts/build.sh"
BIN="${LKM_BUILD_BIN:-lkm-build}"
command -v "$BIN" >/dev/null 2>&1 || {
  echo "error: lkm-build not found — clone https://github.com/L-K-M/release-tool and run ./install.sh" >&2
  exit 1
}
exec "$BIN" "$@"
