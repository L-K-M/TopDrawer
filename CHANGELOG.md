# Changelog

## Unreleased

- The Clear button next to a tab's shortcut recorder hides while the recorder
  is listening; press ⌫ to clear from the keyboard.
- A hotkey press that arrives just as its shortcut is changed or turned off no
  longer fires the old action (Keycap 0.1.1).
- When GitHub's rate limit stops a Check for Updates, the alert says when to
  try again instead of showing a bare HTTP 403 (Updraft 0.2.0).
- Add Quick Look, folder pop-ups, Open With menus, and optional website previews.
- Add keyboard navigation without a search and optional scroll/swipe tab switching.
- Add per-item editing locks, lock-all/new-item controls, per-tab label settings,
  typography, and Glass, Flat, and High Contrast presets.
- Add macOS Clipboard tabs with searchable text history,
  click-to-copy, and individual removal or Clear History.
- Add an opt-in **Keep history after quitting** setting for Clipboard tabs.
- Fix the notes caret jumping to the end of the note after each typed
  character.
- Stored tab and drawer colours accept `#RGB`/`#RGBA` shorthand and keep their
  alpha when written back.
- Per-tab hotkeys now use the shared Keycap package: the recorder captures chords
  that are menu key equivalents, refuses system-reserved shortcuts such as ⌘Q and
  ⇧⌘4 with a beep, and keeps the existing Clear button. A reserved shortcut saved
  by an older version is no longer registered, and the Tabs pane says so under
  the recorder. Key names follow the current keyboard layout.
- Software updates now use the shared Updraft package: downloaded releases are
  size-checked, SHA-256-verified when the release provides a digest, and
  quarantined for Gatekeeper; Linux `.deb` assets on the same release are never
  offered; skipping a version survives a re-tag; a failed download shows an
  alert offering the release page instead of opening it silently; and the
  "Couldn't compare versions" alert now names the string it couldn't read, and
  its button, now called Open Release Page, only opens a page of Top Drawer's
  own repository.
