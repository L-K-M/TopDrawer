# CI/CD — building, testing & releasing Top Drawer

Top Drawer (and its sibling app **Zap**) ship via **GitHub Actions** on macOS runners.
Three workflows do the work, and **none of them needs any secrets or API keys**:

| Workflow | Trigger | What it does |
|---|---|---|
| [`ci.yml`](workflows/ci.yml) | every pull request + push to `main` | `xcodebuild clean test` with **no code signing** — verifies the app builds and the XCTest suite passes |
| [`linux-ci.yml`](workflows/linux-ci.yml) | every pull request + push to `main`; also called by `release.yml` | builds and tests the shared core and the `linux/` daemon + frontend in the pinned `swift:6.3-noble` container (D-Bus tests under a private session bus) |
| [`release.yml`](workflows/release.yml) | pushing a `v*` tag (e.g. `v1.2.0`; `v1.2.0-beta.1` for a pre-release) | builds a Release **without Developer ID signing or notarization**, ad-hoc signs it so it can launch, packages a **DMG** + **zip**, and creates a **GitHub Release** with both attached; separately builds the Linux **`.deb`**, smoke-tests it in a pristine Ubuntu 24.04 container, and attaches it to that release |

The macOS jobs run on `macos-14` (Apple Silicon) with a **pinned Xcode** (`16.2`). There
are no third-party dependencies, so there's nothing to cache or install beyond the build
tools. The Linux jobs run in a digest-pinned Swift container; see
[Linux `.deb`](#linux-deb) below. The two toolchains differ on purpose — Xcode 16.2's
Swift on macOS, Swift 6.3 on Linux — and the shared core must keep compiling under both,
which each platform's CI enforces.

> **Signing/notarization is intentionally off.** Releases are **not** signed with a Developer
> ID and **not** notarized — no certificates, no App Store Connect API key, no secrets. See
> [Unsigned releases](#unsigned-releases-what-users-see) for what that means for users, and
> [Adding Developer ID later](#adding-developer-id-later-optional) if that ever changes.
>
> **Auto-updates (Sparkle)** are also not wired up yet.

---

## Cutting a release

Driven entirely by a **git tag** — no version to edit in the project:

```bash
git tag v1.2.0
git push origin v1.2.0
```

The workflow then:

1. derives `MARKETING_VERSION` from the tag (`v1.2.0` → `1.2.0`) and uses the workflow run
   number as `CURRENT_PROJECT_VERSION` (a monotonic build number);
2. builds the Release configuration with `CODE_SIGNING_ALLOWED=NO`;
3. **ad-hoc signs** the app (`codesign --sign -`) — this needs no certificate or key but is
   required for the app to launch on Apple Silicon;
4. packages `TopDrawer-1.2.0.dmg` and `TopDrawer-1.2.0.zip`;
5. publishes a GitHub Release named `Top Drawer 1.2.0` with auto-generated notes (plus the
   Gatekeeper instructions below) and both files attached;
6. in parallel, builds the Linux `.deb`, smoke-tests it, and attaches it to the same release
   (see [Linux `.deb`](#linux-deb)).

A tag with a **semver pre-release suffix** — `v2.2.0-beta.1` — is published as a GitHub
**pre-release**. The in-app updater asks for `releases/latest`, which excludes pre-releases,
so existing users are not prompted; that is how a Linux test build ships without pushing a
macOS update to everyone. `MARKETING_VERSION` carries the suffix verbatim (`2.2.0-beta.1`),
which the app's `SemanticVersion` parses and ranks *below* the final `2.2.0`.

To redo a botched release, delete the tag and the Release on GitHub, then re-tag.

---

## Linux `.deb`

`release.yml` also produces `TopDrawer-<version>-amd64.deb` for the Linux port (the
`topdrawerd` daemon and the `topdrawer-shell` layer-shell frontend — see
[`linux/README.md`](../linux/README.md)). Four jobs, deliberately decoupled from the macOS
path (a Linux failure never blocks or alters the macOS release; the `.deb` is simply absent):

1. **`linux-test`** reuses `linux-ci.yml` as a `workflow_call`, so the exact Linux CI job
   runs on the tagged commit before anything is packaged.
2. **`linux-deb`** runs in the same digest-pinned `swift:6.3-noble` container Linux CI uses
   (Ubuntu 24.04, so the package installs on 24.04 and newer). It builds gtk4-layer-shell
   v1.3.0 from source via the shared composite action
   [`actions/setup-gtk4-layer-shell`](actions/setup-gtk4-layer-shell/action.yml) (noble
   doesn't package the GTK4 binding), then runs
   [`linux/packaging/build-deb.sh`](../linux/packaging/build-deb.sh): stamps the tag's
   version into `TopDrawerVersion.swift`, builds release binaries with
   `--static-swift-stdlib` (Ubuntu ships no Swift runtime), stages a plain `dpkg-deb`
   tree (`/usr/bin`, the systemd *user* unit, a private `/usr/lib/topdrawer/` copy of
   gtk4-layer-shell reached through an rpath, DEP-5 copyright, changelog), computes
   `Depends` with `dpkg-shlibdeps`, and runs `lintian` (errors fail the job; warnings
   are in the log). A pre-release version maps to Debian's `~` form inside the package
   (`Version: 2.2.0~beta.1`, which sorts before `2.2.0`); the release asset keeps the
   tag's hyphenated spelling (`TopDrawer-2.2.0-beta.1-amd64.deb`), since `~` is unsafe in
   GitHub asset names.
3. **`linux-smoke`** installs the artifact with `apt` into a pristine, digest-pinned
   `ubuntu:24.04` container — so `Depends` must resolve on their own — then checks that
   `topdrawerd --version` and `topdrawer-shell --version` print exactly the tag's version
   (the latter also proves the vendored library loads), and that `Ping` over a throwaway
   `dbus-run-session` bus answers with it.
4. **`publish-linux`** waits for the macOS `release` job, uploads the `.deb` with
   `gh release upload`, appends a Linux section to the release notes, and downloads and
   byte-compares the published asset, removing it on mismatch — the macOS verify rule.

Build it locally with a Swift toolchain, `dpkg-dev`, `binutils`, `lintian`, and
gtk4-layer-shell installed: `linux/packaging/build-deb.sh 2.2.0`.

---

## Unsigned releases: what users see

Because the build isn't Developer-ID-signed or notarized, macOS **Gatekeeper** blocks it on
first launch ("…can't be opened because Apple cannot check it for malicious software"). The
release notes tell users how to open it anyway:

- **Right-click** (or Control-click) the app → **Open** → **Open** (only needed once), or
- `xattr -dr com.apple.quarantine "/Applications/Top Drawer.app"`

The app *is* ad-hoc signed (`codesign -dv` shows `Signature=adhoc`). That's the minimum macOS
requires to run a native arm64 binary — it is **not** a trust signature and does not avoid the
Gatekeeper prompt.

---

## CI details

`ci.yml` builds and runs tests with `CODE_SIGNING_ALLOWED=NO`, so it needs no secrets and runs
on forked-PR branches too. It uploads the `.xcresult` bundle as an artifact when tests fail.

The only project requirement is a **shared scheme** (`MacDring.xcscheme` in `xcshareddata`)
whose Test action covers the test target — `ci.yml` relies on it. (Hardened Runtime and a
Developer ID certificate are **not** required, since we don't notarize.)

---

## Reusing this for Zap (and keeping them in sync)

Zap has the same shape, so its `ci.yml` / `release.yml` are identical except for the `env:`
block at the top of each file:

```yaml
env:
  PROJECT: Zap.xcodeproj
  SCHEME: Zap
  APP_NAME: Zap        # release.yml only
```

Two ways to avoid drift:

1. **Copy** the files into Zap and edit the `env:` block (simplest).
2. **Reusable workflow:** move the jobs into a `workflow_call` workflow (parametrised by
   `project` / `scheme` / `app_name`) hosted in one repo (or a shared `l-k-m/.github` repo),
   and have each app call it. Since there are no secrets, the caller is trivial.

---

## Adding Developer ID later (optional)

If you later want signed + notarized DMGs (no Gatekeeper prompt), the release job would gain:

- a step to import a **Developer ID Application** certificate from a base64 secret into a
  temporary keychain;
- `xcodebuild -exportArchive` with a `developer-id` `ExportOptions.plist` instead of the
  unsigned build;
- `xcrun notarytool submit --wait` (App Store Connect API key) + `xcrun stapler staple`.

That requires these org-level secrets: `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`,
`KEYCHAIN_PASSWORD`, `APPLE_TEAM_ID`, `AC_API_KEY_BASE64`, `AC_API_KEY_ID`, `AC_API_ISSUER_ID`.
Until then, none are needed.

---

## Troubleshooting

- **`built Top Drawer.app not found`** — the Release product path changed; check
  `DerivedData/Build/Products/Release`. Usually means the build failed earlier in the log.
- **`create-dmg` exited non-zero but the DMG looks fine** — known quirk on headless runners
  (it can't set a volume icon). `release.yml` tolerates it by checking the file exists.
- **App won't launch on Apple Silicon** — it must be at least ad-hoc signed; the *Locate &
  ad-hoc sign* step handles this. A truly unsigned arm64 binary is killed by the kernel.
- **Wrong Xcode** — bump `xcode-version` in both workflows together; keep Top Drawer and Zap on
  the same version.
- **Wrong Swift container on a Linux job** — the `swift:6.3-noble` digest is pinned in two
  places (`linux-ci.yml` and `release.yml`'s `linux-deb` job); bump both together so the
  toolchain CI tests is the toolchain that packages, and bump the `ubuntu:24.04` digest of
  `linux-smoke` alongside.
- **`linux-deb` fails in lintian** — the log lists the tags; `build-deb.sh` fails only on
  errors (`E:`). Fix the package layout rather than suppressing, unless the tag is a known
  false positive, in which case add it to the script's `--suppress-tags` list with a reason.
- **`linux-smoke` can't resolve a dependency** — `Depends` come from `dpkg-shlibdeps` on the
  build host (noble); a library only available from a newer release would show here. Build
  against the oldest supported Ubuntu.
- **`topdrawer-shell --version` fails to load `libgtk4-layer-shell.so.0`** — the rpath
  (`/usr/lib/topdrawer`) or the vendored copy is missing; check the `build-deb.sh` output's
  `dpkg-deb --contents` listing.
