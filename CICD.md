# CI/CD

Top Drawer (repository: MacDring) is a Swift/Xcode macOS app with a Linux port in progress under `linux/`. CI builds and tests the app on every change (macOS via Xcode, the shared core and the Linux daemon/frontend via SwiftPM), and the release workflow produces an unsigned, ad-hoc-codesigned `.app` packaged as a `.zip` and `.dmg`, publishes a GitHub Release, and attaches a Linux `.deb`.

## Workflows

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `.github/workflows/ci.yml` | Pull requests and pushes to `main` | Build and test the app with a pinned Xcode toolchain. |
| `.github/workflows/linux-ci.yml` | Pull requests and pushes to `main`; also called by `release.yml` | Build and test the shared core and the `linux/` package (daemon + shell) in the pinned `swift:6.3-noble` container, under a private D-Bus session. |
| `.github/workflows/release.yml` | Pushing a `v*` tag (e.g. `v1.2.0`, or `v1.2.0-beta.1` for a pre-release) | Build an unsigned `.app`, package `.zip` + `.dmg`, and publish a GitHub Release; build the Linux `.deb`, smoke-test it in a pristine Ubuntu 24.04 container, and attach it to that release. |

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

The version is derived from the tag with the leading `v` stripped (e.g. `v1.2.3` → `1.2.3`), and the build number is the workflow run number. The job runs on `macos-14` with Xcode 16.2. A tag with a semver pre-release suffix (`v2.2.0-beta.1`) is published as a GitHub **pre-release**: the in-app updater reads `releases/latest`, which excludes pre-releases, so users are not offered it — the vehicle for a Linux test build.

It produces:

- An **unsigned** Release build of `Top Drawer.app` (`CODE_SIGNING_ALLOWED=NO`), with `MARKETING_VERSION` set from the tag.
- The app is then **ad-hoc codesigned** (`codesign --force --sign -`). This is not a Developer ID signature and the app is not notarized — it is only required so the app can launch on Apple Silicon. The workflow intentionally avoids deprecated `--deep`; if nested code is ever added, sign each nested component explicitly.
- A `TopDrawer-<version>.zip` (via `ditto`) and a `TopDrawer-<version>.dmg` (via `create-dmg`).

Both files are attached to a GitHub Release (named `Top Drawer <version>`, with auto-generated notes) via `softprops/action-gh-release`. The release body explains that, because the app is **unsigned and un-notarized, macOS Gatekeeper warns on first launch**, and tells users to right-click → Open or run `xattr -dr com.apple.quarantine "/Applications/Top Drawer.app"`.

### Linux (`.deb`)

Four more jobs run in parallel with the macOS ones and are deliberately decoupled from them — a Linux failure never blocks or changes the macOS release; the `.deb` is simply absent:

1. **`linux-test`** — `linux-ci.yml` reused as a `workflow_call`, so the exact Linux CI job runs on the tagged commit first.
2. **`linux-deb`** — in the pinned `swift:6.3-noble` container: builds gtk4-layer-shell v1.3.0 from source (the shared composite action `.github/actions/setup-gtk4-layer-shell`), then runs `linux/packaging/build-deb.sh <version>`, which stamps the version, builds `topdrawerd` + `topdrawer-shell` with the Swift runtime linked statically, computes `Depends` with `dpkg-shlibdeps`, vendors gtk4-layer-shell under `/usr/lib/topdrawer/`, and runs `lintian` (errors fail the job). A pre-release version becomes a Debian `~` version (`2.2.0~beta.1`, which sorts before `2.2.0`); the asset is `TopDrawer-<version>-amd64.deb`.
3. **`linux-smoke`** — installs that file with `apt` into a pristine, digest-pinned `ubuntu:24.04` container, runs both executables' `--version`, checks the shell resolved the vendored library, and drives the daemon's `Ping` over a throwaway session bus.
4. **`publish-linux`** — after the macOS release exists: uploads the `.deb` with `gh release upload`, appends a Linux section to the release notes, and downloads and byte-compares the published asset (removing it on mismatch), mirroring the macOS verify step.

## Secrets

None. Neither workflow uses repository secrets beyond the automatically provided `GITHUB_TOKEN` (which `action-gh-release` uses to create the release). Releases are intentionally unsigned, so no Apple certificates or notarization credentials are required.
