# Drawer interactions (macOS)

## Preview and open

Right-click a file or folder for **Quick Look**, or select it with the arrow keys
and press **Space**. The preview closes with Esc or its close button.

**Browse Folder** opens a bounded, folders-first listing without adding its
contents to your layout. **Open in Finder** opens the full directory. An unreadable
folder shows an error and retry action; a large folder shows a truncation notice.
The pop-up is a snapshot, not a replacement for a live Folder tab.

Files offer an **Open With** menu of installed handlers. Missing targets and failed
opens show an error in the drawer. Successful opens follow the tab's keep-open
setting and update Recents.

HTTP(S) links offer **Preview Website**, with an **Open in Browser** action.
Previews use a nonpersistent WebKit data store. Websites may run scripts and load
third-party resources; browser cookies are not shared. Local/custom URL schemes
and downloads are blocked inside previews. Other link types still open externally.
HTTP authentication prompts require opening the page in your browser.

In **Settings → Tabs → Behavior**, choose whether folder items open in Finder or
a folder pop-up, and whether website items open in your browser or a preview.
Existing tabs keep Finder/browser behavior by default.

## Keyboard and gestures

- **Arrows:** select occupied cells without typing. Lists and search results move
  linearly; grids skip gaps and preserve the column where possible.
- **Return:** open the selected item or enter a group.
- **Space:** Quick Look for a selected file/folder, or a website preview for a
  selected web link, when no search is active.
- **Esc:** clear a search, leave a group, then close the drawer.
- **Command-[ / Command-]:** cycle available tabs on the same display edge in
  spatial order (top-to-bottom on side edges, left-to-right on horizontal edges).
- **Scroll/swipe over a tab:** optional in **Settings → General**. Wheel input is
  rate-limited; trackpad momentum does not repeatedly switch tabs. Scrolling drawer
  content still scrolls the content.

Notes, group-name editing, modal dialogs, previews, and input-method composition
retain their own keyboard handling. No global key monitor or Accessibility grant
is added.

## Protect launcher entries

Right-click an Items entry to **Lock Item** or **Unlock Item**. Locks prevent
launcher moves, removal, replacement, renaming, and icon changes. They do not lock
the target file. Locked groups protect their contents, and locked children prevent
their container from being moved or dissolved indirectly.

**Settings → Tabs → Items** offers **Lock All Items**, **Unlock All Items**, and
**Lock newly added items**. Duplicate drops retain the existing entry's lock and
position. New locked entries can still take their initial dropped position.
File drops onto locked folder/application targets continue to move/open the files.
Unlock protected items before removing their containing tab.

## Appearance

**Settings → Tabs → Appearance** offers Glass, Flat, and High Contrast presets.
**System** follows global appearance settings. Item titles can remain visible,
appear on hover, or be hidden with tooltips/accessibility labels retained. Item
and tab text have independent size and weight controls. Extension formatting
preserves custom labels and does not change filenames.

The app remains English-only. Floating docks are not planned. Native Shortcuts
selection is deferred in `BACKLOG.md`.

## Verification

Automated tests cover navigation with gaps/groups/search ranking, gesture gating,
lock mutations and persistence, appearance decoding/formatting, preview URL policy,
folder errors, and Open With completion handling.

Manual macOS checks:

1. Preview a local document and folder on every edge, including a small display
   and another application's fullscreen Space. Verify focus stays in that app.
2. Resize/close a preview; switch tabs or quit during loading. No orphan preview
   or stale callback should appear after reopening another drawer. Start a slow
   application launch, then open a preview; its late completion must not close it.
3. Browse empty, unreadable, large, and network folders. Verify errors, retry,
   truncation, correct click targets, and pop-up dismissal.
4. Choose a compatible application through Open With. Check success, failure,
   keep-open behavior, and Recents. Move the target before invoking the action.
5. Preview a website with redirects, new-window links, a download, a custom-scheme
   link, and a failed load. Check blocked navigation and Open in Browser.
6. Navigate an unfiltered grid with gaps and an open group; type a search with
   spaces and use an input method. Notes and group-name fields must retain keys.
7. Enable scroll switching. Check wheel, trackpad, momentum, wrapping, parked tabs,
   and multiple displays. Drawer scrolling must remain unchanged.
8. Lock items and groups. Try every edit/drop/settings path; unlock again. Check
   locked folder/app file drops and save/relaunch/import/export round-trips.
9. Try presets, hidden/hover titles, extensions, and font bounds in grid/list
   layouts, all four edges, and light/dark appearance. Check VoiceOver labels.
