# CI/CD — building, testing & releasing Top Drawer

Top Drawer (and its sibling app **Zap**) ship via **GitHub Actions** on macOS runners.
Two workflows do the work, and **neither needs any secrets or API keys**:

| Workflow | Trigger | What it does |
|---|---|---|
| [`ci.yml`](workflows/ci.yml) | every pull request + push to `main` | `xcodebuild clean test` with **no code signing** — verifies the app builds and the XCTest suite passes |
| [`release.yml`](workflows/release.yml) | pushing a `v*` tag (e.g. `v1.2.0`) | builds a Release **without Developer ID signing or notarization**, ad-hoc signs it so it can launch, packages a **DMG** + **zip**, and creates a **GitHub Release** with both attached |

Both run on `macos-14` (Apple Silicon) with a **pinned Xcode** (`16.2`). There are no
third-party dependencies, so there's nothing to cache or install beyond the build tools.

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
   Gatekeeper instructions below) and both files attached.

To redo a botched release, delete the tag and the Release on GitHub, then re-tag.

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
