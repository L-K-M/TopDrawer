# Security Policy

## Supported versions

Security fixes are provided for the latest released version of Top Drawer.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature for this repository. Do not include passwords, tokens, or other secrets in a report. If private reporting is unavailable, open an issue that contains no sensitive details and request a private contact channel.

## Security boundary

Top Drawer's security boundary is intentionally narrow: it launches only items the user placed in a drawer, via `NSWorkspace` — no shell and no command construction. Optional per-tab hotkeys use Carbon's `RegisterEventHotKey`, so the app never requests Accessibility access. Its only entitlement is `com.apple.security.automation.apple-events`, used solely to ask Finder to empty the Trash; macOS prompts once before allowing that, and declining only disables Empty Trash.

Network input is treated as untrusted. The update checker speaks HTTPS-only to GitHub's public releases API, refuses non-HTTPS asset URLs, verifies a downloaded archive's size against the release metadata, and saves it to `~/Downloads` for the user to install — it never installs anything itself. Favicons for web-link items are fetched over HTTPS, decoded and downscaled through ImageIO, and kept only in a bounded in-memory cache.

Release builds are ad-hoc signed, not Developer ID signed or notarized, so Gatekeeper warns on first launch. The release pipeline runs the test suite before publishing, pins its GitHub Actions to immutable commit SHAs, and byte-compares the published release assets against the freshly built ones.

(The Xcode project and bundle identifier keep the app's former name, MacDring; the product is Top Drawer.)
