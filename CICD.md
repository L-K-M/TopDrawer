# CI/CD

Top Drawer (repository: MacDring) is a Swift/Xcode macOS app. CI builds and tests the app on every change, and the release workflow produces an unsigned, ad-hoc-codesigned `.app` packaged as a `.zip` and `.dmg`, then publishes a GitHub Release.

## Workflows

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `.github/workflows/ci.yml` | Pull requests and pushes to `main` | Build and test the app with a pinned Xcode toolchain. |
| `.github/workflows/release.yml` | Pushing a `v*` tag (e.g. `v1.2.0`) | Build an unsigned `.app`, package `.zip` + `.dmg`, and publish a GitHub Release. |

## Continuous integration (`ci.yml`)

Runs a single **Build & Test** job on `macos-14`. In-progress runs for the same ref are cancelled when a new commit is pushed.

- Selects **Xcode 16.2** via `maxim-lobanov/setup-xcode` — pinned so a runner-image bump can't silently change the toolchain.
- Installs `xcbeautify` (for readable build logs).
- Runs `xcodebuild clean test` against the `MacDring` scheme in `MacDring.xcodeproj`, destination `platform=macOS`, with `CODE_SIGNING_ALLOWED=NO` (no signing needed for CI), writing results to `TestResults.xcresult`.
- On failure, uploads `TestResults.xcresult` as an artifact named `TestResults`.

### Running CI checks locally

```sh
set -o pipefail
xcodebuild \
  -project MacDring.xcodeproj \
  -scheme MacDring \
  -destination 'platform=macOS' \
  -resultBundlePath TestResults.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  clean test | xcbeautify
```

This requires Xcode 16.2 to match CI exactly. `xcbeautify` is optional (install with `brew install xcbeautify`); drop the pipe to use raw `xcodebuild` output.

## Releases (`release.yml`)

To cut a release:

```
git tag v1.2.3
git push origin v1.2.3
```

Or use the helper, which also bumps the committed `MARKETING_VERSION` so local/dev builds (and the in-app update checker) report the same number, then creates and pushes the tag:

```
scripts/release.sh 1.2.3 --push
```

The version is derived from the tag with the leading `v` stripped (e.g. `v1.2.3` → `1.2.3`), and the build number is the workflow run number. The job runs on `macos-14` with Xcode 16.2.

It produces:

- An **unsigned** Release build of `Top Drawer.app` (`CODE_SIGNING_ALLOWED=NO`), with `MARKETING_VERSION` set from the tag.
- The app is then **ad-hoc codesigned** (`codesign --force --sign -`). This is not a Developer ID signature and the app is not notarized — it is only required so the app can launch on Apple Silicon. The workflow intentionally avoids deprecated `--deep`; if nested code is ever added, sign each nested component explicitly.
- A `TopDrawer-<version>.zip` (via `ditto`) and a `TopDrawer-<version>.dmg` (via `create-dmg`).

Both files are attached to a GitHub Release (named `Top Drawer <version>`, with auto-generated notes) via `softprops/action-gh-release`. The release body explains that, because the app is **unsigned and un-notarized, macOS Gatekeeper warns on first launch**, and tells users to right-click → Open or run `xattr -dr com.apple.quarantine "/Applications/Top Drawer.app"`.

## Secrets

None. Neither workflow uses repository secrets beyond the automatically provided `GITHUB_TOKEN` (which `action-gh-release` uses to create the release). Releases are intentionally unsigned, so no Apple certificates or notarization credentials are required.
