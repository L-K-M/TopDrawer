#!/usr/bin/env bash
# Put the app's license notices into its Resources folder and fail if any is
# missing or empty. Runs as an Xcode Run Script phase (no arguments) or from a
# SwiftPM bundle script, with the bundle's Contents/Resources as argument 1.
# Template from the shared license-notices recipe: copy it to scripts/ and
# edit only the settings block. Bash 3.2 compatible (macOS /bin/bash).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Settings for this repository -----------------------------------------
# Product name for the notices heading.
TITLE="Top Drawer"
# Generated file name; keep an existing name if the app already ships one.
NOTICES_NAME="Third-Party-Notices.txt"
# Package.resolved files whose pins are linked into the app. Leave the array
# empty when the app has no Swift package dependencies.
RESOLVED=(
  "$ROOT/MacDring.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
)
# Explicit overrides for swiftpm-notices.py; empty when none are needed.
OVERRIDES="$ROOT/scripts/third-party-notices.json"
# Files shipped verbatim, as SOURCE=NAME-IN-RESOURCES. Add the root LICENSE
# when it carries someone else's copyright (forks) or a finding asks for it.
COPY=(
  # "$ROOT/LICENSE=LICENSE.txt"
)
# ---------------------------------------------------------------------------

RESOURCES="${1:-${TARGET_BUILD_DIR:?run from Xcode or pass the Resources dir}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}}"
mkdir -p "$RESOURCES"
shipped=()

if [ -n "${RESOLVED[*]+x}" ] && [ -n "${RESOLVED[*]}" ]; then
  args=(--title "$TITLE" --output "$RESOURCES/$NOTICES_NAME")
  for resolved in "${RESOLVED[@]}"; do
    args+=(--resolved "$resolved")
  done
  if [ -n "$OVERRIDES" ]; then args+=(--overrides "$OVERRIDES"); fi
  # Set NOTICES_CHECKOUTS when building with -clonedSourcePackagesDirPath.
  if [ -n "${NOTICES_CHECKOUTS:-}" ]; then args+=(--checkouts "$NOTICES_CHECKOUTS"); fi
  python3 -I "$ROOT/scripts/swiftpm-notices.py" "${args[@]}"
  shipped+=("$RESOURCES/$NOTICES_NAME")
fi

for entry in ${COPY[@]+"${COPY[@]}"}; do
  src="${entry%%=*}"
  name="${entry#*=}"
  if [ ! -s "$src" ]; then
    echo "error: license file missing or empty: $src" >&2
    exit 1
  fi
  install -m 0644 "$src" "$RESOURCES/$name"
  shipped+=("$RESOURCES/$name")
done

if [ -z "${shipped[*]+x}" ]; then
  echo "error: nothing to ship: set RESOLVED or COPY in $0" >&2
  exit 1
fi
for file in "${shipped[@]}"; do
  if [ ! -s "$file" ]; then
    echo "error: $file is missing or empty" >&2
    exit 1
  fi
done
