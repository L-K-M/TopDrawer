# Top Drawer Privacy Policy

Effective August 16, 2026

Top Drawer does not operate an account or analytics service, and it does not sell personal data. It contains no advertising, telemetry, or tracking.

Everything the app knows stays on the user's Mac. Tabs, their items, and notes are stored as JSON in `~/Library/Application Support/MacDring/launcher.json`, and app-wide settings live in macOS user defaults under the `com.macdring.MacDring` domain — MacDring is the app's former name, which the bundle identifier and support folder keep so existing installs retain their data. The history behind Recents tabs is recorded locally, and Fresh and Recents tabs otherwise read the Mac's own Spotlight index. Layout exports are written only to a file the user chooses. Nothing is synced or uploaded.

Top Drawer makes exactly two kinds of network request:

- **Update checks.** On launch and about once a day — and whenever the user picks *Check for Updates…* — it asks GitHub's public releases API over HTTPS whether a newer version exists. The request carries no account, identifier, or system profile; the only app-specific field is the bundle identifier sent as the required User-Agent header. Like any network request, GitHub receives ordinary connection metadata such as the source IP address. Automatic checks can be turned off in Settings. If the user chooses **Download** for an offered update, the release archive is fetched over HTTPS into `~/Downloads`; nothing installs automatically.
- **Favicons.** For web links the user has added, Top Drawer fetches `https://<host>/favicon.ico` from that link's own site to show its icon in the drawer. Icons are kept in memory for the session only and are never written to disk.

Top Drawer's core features need no special macOS permissions — launching uses `NSWorkspace`, and hotkeys use Carbon rather than Accessibility. Two optional features each prompt only when used: **Empty Trash** asks Finder to empty the Trash via Apple Events, which macOS confirms with a one-time prompt; and the Fresh tabs' **direct folder check** (off by default) makes macOS ask once per folder for access to Downloads, Desktop, and Documents. Declining either simply leaves that feature off.

Removing Top Drawer and its Application Support folder removes all of its data. Questions or security reports can be submitted through the project's GitHub repository.
