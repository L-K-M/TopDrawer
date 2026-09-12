#!/usr/bin/env bash
# Fails when the two halves of the notes-editor bridge protocol disagree on its
# version. The app and the bundled web editor each pin the number, and they ship
# together inside one app bundle, so a mismatch is always a mistake — but nothing
# else catches it: the host only logs a diagnostic at runtime, `editor-web.yml`
# is path-filtered to EditorWeb/, and `ci.yml` checks only that the bundled
# assets exist. Run from CI on every pull request, and by hand after touching
# either constant.
#
# Usage: scripts/check-notes-protocol-version.sh
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
swift_file="$repo/MacDring/Notes/NotesEditorBridge.swift"
editor_file="$repo/EditorWeb/src/bridge.ts"

# Both declarations are plain integer literals, so reading them needs no
# toolchain. An empty capture means the declaration moved or was renamed, which
# is reported rather than silently compared as equal.
host=$(sed -nE 's/^[[:space:]]*static let version = ([0-9]+).*/\1/p' "$swift_file")
editor=$(sed -nE 's/^export const PROTOCOL_VERSION = ([0-9]+);.*/\1/p' "$editor_file")

if [[ -z "$host" ]]; then
  echo "error: could not read \`static let version\` from $swift_file" >&2
  exit 1
fi
if [[ -z "$editor" ]]; then
  echo "error: could not read \`PROTOCOL_VERSION\` from $editor_file" >&2
  exit 1
fi

if [[ "$host" != "$editor" ]]; then
  cat >&2 <<EOF
error: the notes-editor bridge protocol versions disagree.

  NotesEditorProtocol.version = $host   (MacDring/Notes/NotesEditorBridge.swift)
  PROTOCOL_VERSION            = $editor   (EditorWeb/src/bridge.ts)

Both halves ship in the same app bundle, so they must move together. Bump
whichever is behind, and update the tests that pin the number:
MacDringTests/NotesEditorBridgeTests.swift and EditorWeb/tests/bridge.test.ts.
EOF
  exit 1
fi

echo "ok: notes-editor bridge protocol version $host on both sides"
