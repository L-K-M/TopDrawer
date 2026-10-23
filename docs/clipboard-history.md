# Clipboard history

On macOS, choose **New Clipboard Tab…** from the menu bar. Recording starts when
you create the tab and continues while any Clipboard tab exists, even with its
drawer closed. Copies made before recording starts are excluded.

- Copy text in any app. Open the drawer to see the newest copies first.
- Click an entry, then paste with **⌘V** in your app. This copies plain text;
  links stay text rather than opening a browser.
- Type to filter the full text. **↑/↓** select; **Return** copies; **Esc** clears
  the filter, then closes the drawer.
- Right-click an entry to remove it. The header's trash button clears all history
  without changing your current system clipboard.
- **Settings → Tabs → Keep open after copying** leaves the drawer open after a
  copy. In the same tab's **Drawer** settings, **Columns** and **Rows** set its size;
  entries scroll in a list.

All Clipboard tabs share the last **50 distinct text copies**. Repeated text moves
to the front. Each entry is limited to **256 KiB**; larger copies are skipped,
never truncated. Blank text, images, and files are skipped. Rich text is captured
only through its plain-text representation.

History stays in memory and clears on quit by default. To retain it, enable
**Settings → Tabs → Clipboard → Keep history after quitting**. This applies to all
Clipboard tabs and saves current and future entries, including exact text and
timestamps, to `~/Library/Application Support/MacDring/Clipboard/history.json`.
The file is unencrypted, in an owner-only directory, and excluded from layout
saves and exports. Backups may retain older copies.

Turning retention off deletes the saved copy but keeps the current session's
entries. Remove updates saved history; Clear or removing the last Clipboard tab
erases both memory and disk history. Writes are coalesced for 0.3 seconds and
flushed on normal quit; an abrupt termination may lose the most recent copy.
Storage errors appear in the drawer. An unreadable archive is preserved until
you clear history or disable retention.

Copies marked confidential, transient, or auto-generated are skipped, including
the legacy 1Password marker.
Unmarked text can still contain sensitive information; use Remove or Clear to
discard it. Recording polls every half-second, so rapid intervening copies can
be missed. The experimental Linux frontend does not record clipboard history.

On macOS 15.4+, the system may ask for clipboard access. To record copies in the
background, allow Top Drawer in the system's per-app clipboard settings. Denying
access prevents recording; existing history can still be cleared. This follows
[Apple's pasteboard access controls](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum).

## Manual verification

Requires a macOS GUI session:

1. With retention off, copy text before creating a Clipboard tab. Create it;
   history starts empty.
2. Close the drawer. Copy two different multiline strings, allowing a second
   between copies. Reopen; verify newest-first previews and exact pasted text.
3. Search for text beyond a preview. Use arrows and Return to copy it. Confirm
   the frontmost app stays active and can receive **⌘V** after the drawer closes.
4. Enable **Keep open after copying**. Copy an older entry; it moves to the front
   without duplicates. Remove it; clear the remaining history.
5. Create a second Clipboard tab. Verify shared history, then remove one tab;
   recording continues. Remove the last one, copy text, and recreate a tab;
   history starts empty. Quit and relaunch; verify history is empty again.
6. Enable **Keep history after quitting** in a Clipboard tab's settings. Copy
   multiline text, quit, and relaunch; verify order, timestamps, and exact pasted
   text survive. Confirm the setting is shared by another Clipboard tab. Turn it
   off: current entries remain, but the archive disappears and quit clears them.
   Re-enable retention; verify Remove, Clear, and last-tab removal update or erase
   the archive and no cleared entries return after relaunch.
7. Check light/dark appearance, each screen edge, another display, and an app's
   full-screen Space. Verify scrolling, search, and the riding tab's placement.
8. On macOS 15.4+, verify the clipboard prompt and allow/deny behavior in System
   Settings. CI's macOS 14 runner does not exercise these privacy controls.
