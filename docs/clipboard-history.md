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
  copy. Columns and rows set its size; entries scroll in a list.

All Clipboard tabs share the last **50 distinct text copies**. Repeated text moves
to the front. Each entry is limited to **256 KiB**; larger copies are skipped,
never truncated. Blank text, images, and files are skipped. Rich text is captured
only through its plain-text representation.

History stays in memory. It is excluded from layout saves and exports, and clears
when you quit or remove the last Clipboard tab. Copies marked confidential,
transient, or auto-generated are skipped, including the legacy 1Password marker.
Unmarked text can still contain sensitive information; use Remove or Clear to
discard it. Recording polls every half-second, so rapid intervening copies can
be missed. The experimental Linux frontend does not record clipboard history.

## Manual verification

Requires a macOS GUI session:

1. Copy text before creating a Clipboard tab. Create it; history starts empty.
2. Close the drawer. Copy two different multiline strings, allowing a second
   between copies. Reopen; verify newest-first previews and exact pasted text.
3. Search for text beyond a preview. Use arrows and Return to copy it. Confirm
   the frontmost app stays active and can receive **⌘V** after the drawer closes.
4. Enable **Keep open after copying**. Copy an older entry; it moves to the front
   without duplicates. Remove it; clear the remaining history.
5. Create a second Clipboard tab. Verify shared history, then remove one tab;
   recording continues. Remove the last one, copy text, and recreate a tab;
   history starts empty. Quit and relaunch; verify history is empty again.
6. Check light/dark appearance, each screen edge, another display, and an app's
   full-screen Space. Verify scrolling, search, and the riding tab's placement.
