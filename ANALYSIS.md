# Top Drawer: remaining review findings

Reviewed 24 October 2026 against `origin/main` at `ec1d743a80710fd6c49a35b0c5ed20b2439cb64e`.
Assumed load: one desktop user, dozens of tabs, hundreds of launcher entries, and occasional large or remote folders. The experimental Linux port is included.

All eight focus areas were covered. No blocking finding was established. Findings implemented in open PRs are omitted. Remaining findings follow the requested severity order.

Evidence is source, callers, tests, repository documentation, workflows, and the committed screenshot. macOS layout, focus, VoiceOver, multi-display behavior, and Linux compositor interactions need on-device verification. The retained EditorWeb harness is not the shipping notes editor; its runtime was not audited. Shared-core tests became runnable after local-only configuration of this host's relocated Swift SDK.

### Duplicate layout identities make entries ambiguous (SOL-02)

bugs — important

`MacDring/Store/TabStore.swift:133-145,302-316` accepts duplicate identities. `MacDring/Tabs/TabController.swift:237-240` gives two tabs sharing a UUID one window. Duplicate item UUIDs within a tab make edits and drop targets select an ambiguous entry, including children in groups. This affects imported or hand-edited layouts.

Reject duplicate tab IDs and per-tab item/container IDs before accepting a document. Failed import must retain the existing layout; invalid on-disk originals must survive recovery. The same item UUID in different tabs can remain valid because operations include tab identity. Add import and recovery regressions. Effort: about half a day.

### Partial launcher recovery can become permanent data loss (SOL-03)

bugs — important

`MacDring/Model/LauncherDocument.swift:24-25` and `MacDring/Model/Tab.swift:133-135` drop unreadable records. `MacDring/Store/TabStore.swift:141-145,799-801` accepts a partially recovered document; successive autosaves eventually replace both primary and backup with that reduced document. Reproduce with one valid tab and one invalid anchor, then mutate and save twice.

Retain a recovery original whenever decoding loses records and expose that recovery before accepting destructive rewrites. Preserve working tabs while making omissions visible. Effort: one day.

### Future-version documents accept edits that cannot persist (SOL-04)

bugs — important

`MacDring/Store/TabStore.swift:761-766,788-790` allows mutations but refuses saving a newer schema. Users can type notes or rearrange launchers, then lose those changes on restart without a visible explanation.

Expose read-only store health and disable mutations until an explicit supported replacement/import is chosen. Retain the existing refusal to overwrite newer data. Effort: one day.

### Linux mount escaping corrupts non-ASCII names (SOL-05)

bugs — important

`linux/Sources/TopDrawerDaemon/LinuxVolumes.swift:50-67` appends individual UTF-8 bytes as Unicode scalars whenever a field contains an escape. A mount named `Clé\040USB` becomes `ClÃ© USB`; displayed paths and network/cloud unmount targets become invalid. Accented and non-Latin mount names containing escaped characters are affected.

Accumulate decoded bytes, then decode UTF-8 once. Bound octal conversion so malformed escapes cannot trap. Add mixed Unicode/escape fixtures. Effort: about one hour.

### Filing onto a closed folder pill loses Undo (SOL-06)

bugs — important

`MacDring/Tabs/TabController.swift:940-942,1469-1485` moves files and creates Undo before opening the destination drawer. `MacDring/Drawer/DrawerWindowController.swift:378-385` then clears that action. Users filing through a closed folder pill must reverse the move manually.

Associate the move result with the destination session and publish Undo after opening that drawer. Verify a closed destination and a different drawer already open. Effort: half a day.

### Group-name drafts disappear on uncommitted exits (SOL-07)

bugs — important

`MacDring/Drawer/DrawerView.swift:107-108,306-339` commits only through Return or Back. Switching tabs or closing the drawer without either discards the draft, although the group header promises commit when leaving. `MacDring/Drawer/DrawerWindowController.swift:226` resets group context on open.

Commit the draft against its originating group on focus/session exit, with lock and stale-session checks. Verify tab switching, click-outside, and Return on macOS. Effort: half a day.

### Filing, Undo, and eject failures lack actionable feedback (SOL-09)

general issues — important

`MacDring/Tabs/TabController.swift:917,921,1381-1383,1444,1470-1477` ignores or logs several operation results. Partial moves show a success-only count for the subset moved; failed Undo, eject, and open-with drops leave users unsure what happened or where their files went.

Return per-operation results, retain retryable failures, and show an accessible error alongside any completed subset. Extend the existing ordinary-launch error banner rather than adding another reporting mechanism. Effort: one to two days.

### Pending login approval is represented as unknown or enabled (SOL-10)

general issues — important

`MacDring/Model/LoginItemManaging.swift:24-41` omits approval-pending state. `MacDring/Model/Preferences.swift:238-239,303-308` can retain an enabled toggle although launch at login will not happen. Disabling does not unregister a pending registration.

Represent approval-pending explicitly, offer Open Login Items, and unregister pending registrations when disabled. Verify the real ServiceManagement approval flow. Effort: half a day plus macOS verification.

### File moves and their Undo block the UI (SOL-12)

performance problems, stuttering, and jank — important

`MacDring/Tabs/TabController.swift:1469-1477` calls `MacDring/Launch/FileMover.swift:17-38,45-56` synchronously. Moving a multi-GB file across volumes copies it on the main thread, freezing all tabs and drawers. Undo repeats the stall.

Move execution behind an asynchronous filing service, expose progress, and deliver session-scoped results on main. Test successful and partial moves, plus switching drawers while work runs. Effort: one day.

### Opening live drawers performs synchronous directory scans (SOL-13)

performance problems, stuttering, and jank — important

`MacDring/Drawer/DrawerWindowController.swift:408-413,442-446` enumerates folders and opt-in Fresh scopes on main. `MacDring/Tabs/TabController.swift:1675-1676` repeats the initial Fresh scan. `MacDring/Store/FolderLister.swift:48-59` enumerates and sorts before applying the 300-item display limit, so a large or disconnected network folder can freeze opening and refresh.

Use a generation-checked background listing with explicit loading/error state, reusing the existing FolderBrowserModel pattern. Share the initial Fresh snapshot. The result limit must not be mistaken for bounded enumeration time. Effort: one day.

### Settings resolves file icons inside its render path (SOL-14)

performance problems, stuttering, and jank — important

`MacDring/Settings/TabsView.swift:304-307` calls icon resolution during each body evaluation. `MacDring/Drawer/ItemView.swift:213-228,495-574` shows that this work resolves bookmarks and reads icons from disk. Large launchers, stale bookmarks, or remote targets can beachball Settings repeatedly.

Resolve row icons asynchronously, keyed by the item, with a placeholder and cancellation. Reuse the drawer's resolution approach. Profile opening and changing settings for a 100-entry tab. Effort: half a day.

### A Linux launch can wedge the daemon despite its timeout (SOL-15)

performance problems, stuttering, and jank — important

`linux/Sources/TopDrawerDaemon/LinuxProcess.swift:24-46` waits for pipe EOF before process completion. A launched grandchild inheriting stdout keeps that read waiting after the direct child exits; the watchdog no longer acts. Serial D-Bus dispatch through `TopDrawerService.swift:142-144` then stops answering unrelated requests. Slow eject/stat calls also stall that dispatch path. This was source-verified against the pinned D-Bus client, not reproduced on a live bus.

Stop capturing unused launch output, bound completion independently of inherited descriptors, and move blocking operations off serial dispatch. Regression: a child exits while a grandchild retains stdout; a concurrent Ping must still complete. Effort: one day.

### Portable imports have no display mapping (SOL-16)

missing features — important

`MacDring/Settings/TabsView.swift:108-124` imports foreign display UUIDs unchanged. Under the default policy, `MacDring/Screens/TabPlacementPolicy.swift:31-35` parks every tab whose display is unknown. Users moving layouts between Macs can get an apparently empty launcher, and the enabled status-menu rows cannot open the parked drawers.

Map unknown imported displays to a chosen connected display. Keep same-machine restoration separate from portable import. Verify an export from another display UUID set. Effort: one day.

### Deleting a notes tab has no recovery step (SOL-17)

missing features — important

`MacDring/Settings/TabsView.swift:151-154`, `MacDring/Tabs/TabStripView.swift:59-61`, and `MacDring/Store/TabStore.swift:168-174` remove an unlocked tab immediately. One Remove Tab action destroys all its note text, without confirmation or document Undo.

Confirm deletion of nonempty notes/populated tabs or offer document-level Undo. Preserve the lock rules and verify both deletion surfaces. Effort: half a day for confirmation, longer for shared Undo.

### A maximum-size drawer can push its pill off-screen (SOL-20)

visual issues and layout problems — important

`MacDring/Drawer/DrawerMetrics.swift:135-136` allows an items drawer to consume screen depth minus 16 points. The riding pill is at least 24 points thick, and `MacDring/Screens/EdgeLayout.swift:160-180` adds it and a 22-point animation nudge outside that allowance. Unlike notes at `DrawerWindowController.swift:510-517`, large items drawers can strand the close target or spill onto an adjacent display.

Bound one combined drawer/pill/animation envelope for every edge. Add pure containment cases for small visible frames, then check real display behavior. Effort: half a day plus macOS verification.

### Passive hover can redirect keyboard focus (SOL-22)

usability: speed, convenience, and clarity — important

`MacDring/Tabs/TabController.swift:557-567,961-967` opens drawers from hover and spring loading. `MacDring/Drawer/DrawerWindowController.swift:268-270` makes them key, and `MacDring/Drawer/DrawerView.swift:152` focuses search. Crossing a hover-enabled tab can redirect typing from the previous app even while Top Drawer remains nonactivating.

Carry an open-reason enum. Hover/spring opens should remain pointer-only until explicit input intent. Verify macOS, input methods, and fullscreen behavior. Do not add a global key monitor. Effort: one day plus device verification.

### Primary tab surfaces lack explicit accessible activation (SOL-23)

usability: speed, convenience, and clarity — important

`MacDring/Tabs/TabStripView.swift:33-63` provides gestures and a tooltip without explicit accessible button activation, title, or open state. With labels hidden, VoiceOver users lack a reliable way to identify and toggle a tab. `MacDring/Drawer/ItemView.swift:124-126` also omits running/broken state. Exact announcements remain unverified on Linux.

Expose one labeled accessible element per control, button activation, open/selected state, and meaningful item status. Verify with VoiceOver and Accessibility Inspector. Effort: one day including assistive-technology checks.

### Shortcut recording consumes keys after defocus (SOL-24)

usability: speed, convenience, and clarity — important

`MacDring/Settings/HotkeyRecorderView.swift:24,37-52` keeps its app-wide local key monitor armed until capture, cancellation, or disappearance. Click Record Shortcut, then click Name and type: ordinary keys vanish, while a later usable command can unexpectedly become the hotkey.

Scope capture to a focused recorder and cancel on focus/window loss or outside click. Verify text entry, normal shortcuts, and window switching. Effort: half a day plus AppKit verification.

### Folder and Trash drops advertise Copy while removing the source (SOL-25)

usability: speed, convenience, and clarity — important

`MacDring/Drawer/DrawerWindowController.swift:66-77` always returns the Copy drag operation. `MacDring/Tabs/TabController.swift:920-942` can instead move files or trash them. The plus-badge cursor misleads users during file operations.

Derive drag operation from target and source mask. Distinguish add-reference, open-with, move/copy, and Trash, with supported modifier behavior. Verify Finder and cross-volume drops. Effort: one day plus device checks.

### Retained web-editor docs describe a shipping integration (SOL-11)

general issues — nice-to-have

`EditorWeb/README.md:3-6,29-35,135-136` describes a current app payload and two shipping hosts, contradicting `README.md:125-148`. Maintainers can debug the wrong notes editor or mistake the retained bundle for the app's current integration.

Label it as a standalone retained harness. Describe its host contract as historical/available integration and link to the native notes editor. Effort: about one hour.

### Broken launchers have no Relink action (SOL-18)

missing features — nice-to-have

`MacDring/Drawer/ItemView.swift:113-192` dims missing targets but provides no Relink action. When both bookmark and fallback fail, users must delete and re-add the item, losing placement, name, and customization.

Offer a file picker that replaces only the target/bookmark after validating its kind, through the existing store/service boundary. Effort: half a day.

### Keyboard navigation does not expose item actions (SOL-19)

missing features — nice-to-have

`MacDring/Tabs/TabController.swift:1814-1847` handles arrows, Return, and Space, but the actions in `MacDring/Drawer/ItemView.swift:127-192` remain mouse-oriented. Keyboard-only users cannot invoke Rename, Lock, Reveal, Open With, or Eject through the current selection.

Add a selected-item actions shortcut and accessible named actions. Effort: one day plus assistive-technology checks.

### Metadata columns use configured rather than visible width (SOL-21)

visual issues and layout problems — nice-to-have

`MacDring/Drawer/ItemView.swift:107-109,362-368` chooses fixed metadata columns from nominal column/icon settings. `MacDring/Drawer/DrawerMetrics.swift:135` can clamp the actual panel much narrower. On narrow displays, Size/Kind can squeeze names or overflow available width.

Choose metadata columns from measured available row width after clamping. Verify large-icon list layout on a narrow screen. Effort: half a day.

### Translucent pill contrast is chosen from the tint alone (SOL-26)

aesthetics and theming — nice-to-have

`MacDring/Model/ColorHex.swift:62-65` chooses foreground from tint luminance, while `MacDring/Tabs/TabStripView.swift:96-111` renders idle fill at 62% opacity. A middle-dark tint selects white text, but bright underlying content can reduce contrast. This is a source-derived visual risk, not a measured current-screen contrast failure.

Use a sufficiently opaque label backing or a tested composited palette. Check light, dark, and busy wallpapers. Effort: half a day.

### Appearance choices lack a live contextual preview (SOL-27)

aesthetics and theming — nice-to-have

`MacDring/Settings/TabAppearanceEditor.swift:7-32` offers presets, hidden labels, and typography without a representative preview. Users must repeatedly open a drawer to judge those choices.

Add a small tab-and-items preview using the existing view styles, bound to the same settings values. Effort: one day.

### Explain the pending drop before releasing it (SOL-28)

novel, delightful, or quirky ideas worth trying — nice-to-have

`MacDring/Drawer/DrawerWindowController.swift:66-77` and `MacDring/Drawer/DrawerView.swift:397-436` show a target ring without explaining the pending action. New users must remember whether a tile opens, files, trashes, or adds a launcher.

After a brief dwell, show target-specific text such as “Move to Downloads” or “Open with Preview,” using the same operation policy as the cursor. Test whether it reduces hesitation without obscuring the target. Effort: half a day after SOL-25.

### Offer non-destructive starter drawer kits (SOL-29)

novel, delightful, or quirky ideas worth trying — nice-to-have

`MacDring/AppDelegate.swift:274-328` supplies Apps/Welcome. Useful Folder/Fresh/Notes combinations still require manual discovery; the import flow at `MacDring/Settings/TabsView.swift:108-124` replaces the entire layout.

Offer a few optional local kits, such as “Downloads desk” with Folder, Fresh, and Notes, added without replacing current tabs and removable in one action. Reuse existing tab types; no automation or permissions are needed. Effort: one to two days.
