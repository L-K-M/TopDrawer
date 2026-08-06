import SwiftUI
import AppKit
import PictKit

/// One launchable entry inside a drawer — icon + label, with a context menu and
/// single/double-click launch. Broken items (missing target) render dimmed.
struct ItemView: View {
    let item: DrawerItem
    let iconSize: CGFloat
    let layout: DrawerLayout
    /// The tab's configured grid columns — a stand-in for the list's width, deciding
    /// how many metadata columns fit: Date always, Size at ≥ 3 columns, Kind at ≥ 4.
    var listColumns: Int = 4
    let launchOnSingleClick: Bool
    var onLaunch: () -> Void
    var onReveal: () -> Void
    var onRemove: (() -> Void)?
    var onRename: (() -> Void)?
    var onChangeIcon: (() -> Void)?
    var onResetIcon: (() -> Void)?
    var onEmptyTrash: (() -> Void)?
    /// Bumped by the drawer to force a fresh icon even when `item` is unchanged.
    var iconNonce: Int = 0
    var onEject: (() -> Void)?
    /// Open the generated-icon editor for this item (available for every item).
    var onCustomizeIcon: (() -> Void)?
    /// Pop this item out of its group back to the top level — set only while a group
    /// is open, so the row offers "Move Out of Group".
    var onUngroup: (() -> Void)?
    /// Bundle IDs of currently-running apps — drives the "running" dot on app items.
    var runningBundleIDs: Set<String> = []
    /// This disk item is being ejected (Eject All) — shows a spinner over its icon.
    var isEjecting: Bool = false
    /// This item just arrived (a Fresh listing) — plays a one-shot sparkle.
    var sparkle: Bool = false

    // Icon and broken-ness are resolved in `.task` (once per item change) on a
    // *detached* task and cached here, so neither `body` nor the main thread does
    // disk I/O per cell — important for a large or network-volume folder tab.
    // See BACKLOG.md's legacy ID index (I2) and FP1 / PR #65.
    @State private var icon: NSImage?
    @State private var broken = false
    /// An app item's bundle id (resolved off the render path, like the icon), so the
    /// running dot is a cheap `Set.contains` in `body`.
    @State private var bundleID: String?
    /// File size and localized kind for the list layout's columns, resolved off the
    /// render path (only in list mode). `nil` for folders / non-file items.
    @State private var byteSize: Int64?
    @State private var typeDescription: String?
    /// The Trash's item count for the count badge (resolved off the render path, like
    /// the icon). 0 hides the badge.
    @State private var trashCount = 0
    /// Drives the one-shot sparkle fade for a newly-arrived Fresh item.
    @State private var sparkleOpacity: Double = 0
    /// Up to four child icons for a `.group`'s mini-preview (resolved off the render path).
    @State private var groupPreviewIcons: [NSImage] = []
    @State private var groupPreviewItemID: UUID?

    /// Finder-style small icon for the list layout, regardless of the grid's icon size.
    static let listIconSize: CGFloat = 16

    /// The icon's rendered size: a fixed small glyph in list mode, the configured size
    /// in grid mode.
    private var effectiveIconSize: CGFloat { layout == .list ? Self.listIconSize : iconSize }

    /// Which metadata columns fit at this list's actual width (which depends on the
    /// configured columns *and* the icon size) — so a narrow drawer drops Size/Kind
    /// rather than overflowing.
    private var listMeta: (size: Bool, kind: Bool) {
        DrawerMetrics.listMetaColumns(forWidth: DrawerMetrics.listWidth(columns: listColumns, iconSize: iconSize))
    }

    var body: some View {
        cell
            .opacity(broken ? 0.45 : 1)
            .contentShape(Rectangle())
            // ⌘-click reveals the target in Finder instead of opening it (Finder-style).
            .onTapGesture(count: launchOnSingleClick ? 1 : 2) {
                if NSEvent.modifierFlags.contains(.command), item.kind != .url, !item.isGroup {
                    onReveal()
                } else {
                    onLaunch()   // a group opens instead of launching
                }
            }
            .help(broken ? "\(item.displayName) — can’t find this item" : item.displayName)
            .contextMenu {
                Button(groupOrKindOpenTitle, action: onLaunch)
                if item.kind != .url, !item.isGroup {
                    Button("Reveal in Finder", action: onReveal)
                }
                if let onEject {
                    Divider()
                    Button("Eject", action: onEject)
                }
                if item.kind == .trash, let onEmptyTrash {
                    Divider()
                    Button("Empty Trash…", action: onEmptyTrash)
                        .disabled(TrashInspector.trashIsEmpty())
                }
                // Groups get rename but no icon customization (their icon is a preview).
                if let onRename, item.isGroup {
                    Divider()
                    Button("Rename…", action: onRename)
                } else if !item.isGroup, onRename != nil || onChangeIcon != nil || onCustomizeIcon != nil {
                    Divider()
                    if let onRename { Button("Rename…", action: onRename) }
                    if let onCustomizeIcon { Button("Customize Icon…", action: onCustomizeIcon) }
                    if let onChangeIcon { Button("Change Icon…", action: onChangeIcon) }
                    if (item.customIconBookmark != nil || item.iconStyle != nil), let onResetIcon {
                        Button("Reset Icon", action: onResetIcon)
                    }
                    // Two verbs, named for their scope. The ones above change *this
                    // item*; this changes *the app*, everywhere — Zap's switcher and
                    // Jetty's dock included. A change with reach the user didn't ask
                    // for is the failure mode worth designing against, so the reach
                    // is written on the button.
                    if let target = TopDrawerIcons.target(for: item) {
                        Divider()
                        if PictURL.installedAppURL() != nil {
                            Button("Change \(item.displayName)'s Icon Everywhere…") {
                                PictURL.open(selecting: target)
                            }
                        } else {
                            Button("Get Pict to Change Icons Everywhere…") {
                                if let url = PictURL.homepage { NSWorkspace.shared.open(url) }
                            }
                        }
                    }
                }
                if let onUngroup, !item.isGroup {
                    Divider()
                    Button("Move Out of Group", action: onUngroup)
                }
                if let onRemove {
                    Divider()
                    Button(item.isGroup ? "Delete Group" : "Remove", role: .destructive, action: onRemove)
                }
            }
            // Keyed by the item — a reorder swap into this (slot-keyed, reused) cell,
            // a rename, or a custom-icon change — and, for a Trash item only, by
            // `iconNonce` (bumped when the Trash's contents change). Other kinds pass
            // a constant nonce so a Trash event doesn't re-resolve the whole drawer.
            .task(id: ResolveKey(item: item, nonce: item.kind == .trash ? iconNonce : 0, list: layout == .list)) {
                if item.isGroup {
                    // A group renders a mini-preview of its children, not a single icon.
                    // Resolve them off the main actor too (bounded to the first four).
                    let itemID = item.id
                    let children = Array(item.children.prefix(4))
                    let previews = await Task.detached(priority: .userInitiated) {
                        children.map { ItemView.resolveIcon($0) }
                    }.value
                    guard !Task.isCancelled else { return }
                    groupPreviewIcons = previews
                    groupPreviewItemID = itemID
                    broken = false
                    return
                }
                // Everything below does filesystem work (bookmark resolution, stat,
                // icon decode; a per-volume sweep for the Trash count). `.task`
                // inherits the view's MainActor context, so hop to a detached task —
                // otherwise a large drawer serializes hundreds of blocking calls on
                // the main thread, merely deferred out of `body`.
                let item = item
                let wantsListMeta = layout == .list
                let resolved = await Task.detached(priority: .userInitiated) { () -> Resolution in
                    let meta: (size: Int64?, kind: String?) =
                        wantsListMeta ? ItemView.resolveMetadata(item) : (nil, nil)
                    return Resolution(icon: ItemView.resolveIcon(item),
                                      broken: BookmarkResolver.isBroken(item),
                                      bundleID: ItemView.appBundleID(item),
                                      byteSize: meta.size,
                                      typeDescription: meta.kind,
                                      trashCount: item.kind == .trash ? TrashInspector.trashCount() : 0)
                }.value
                guard !Task.isCancelled else { return }
                icon = resolved.icon
                broken = resolved.broken
                bundleID = resolved.bundleID
                byteSize = resolved.byteSize
                typeDescription = resolved.typeDescription
                trashCount = resolved.trashCount
                // Best-effort: swap the globe for the site's favicon once fetched —
                // but never over a user-chosen icon (image or generated style).
                if item.kind == .url, item.customIconBookmark == nil, item.iconStyle == nil,
                   let url = item.url,
                   let favicon = await FaviconCache.shared.fetch(for: url), !Task.isCancelled {
                    icon = favicon
                }
            }
    }

    /// Re-resolve key: the item, the Trash nonce (constant for non-trash items), and
    /// whether the list columns are shown (so a grid→list switch re-resolves metadata).
    private struct ResolveKey: Equatable { let item: DrawerItem; let nonce: Int; let list: Bool }

    /// Everything the `.task` resolves off the main actor in one hop.
    private struct Resolution {
        let icon: NSImage
        let broken: Bool
        let bundleID: String?
        let byteSize: Int64?
        let typeDescription: String?
        let trashCount: Int
    }

    @ViewBuilder
    private var cell: some View {
        if item.isGroup {
            groupCell
        } else if layout == .grid {
            VStack(spacing: 5) {
                iconImage
                Text(item.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: iconSize + 28)
            }
        } else {
            // A Finder-style row: small icon + name, then a metadata table (date / size
            // / kind) in fixed columns so they line up down the list. Columns reserve
            // their width even when empty (apps / links have no date or size).
            HStack(spacing: 8) {
                iconImage
                Text(item.displayName)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                metaColumn(item.date.map(ItemView.listDate) ?? "", width: 96, alignment: .trailing)
                if listMeta.size {
                    metaColumn(byteSize.map(ItemView.listSize) ?? "", width: 52, alignment: .trailing)
                }
                if listMeta.kind {
                    metaColumn(typeDescription ?? "", width: 76, alignment: .leading)
                }
            }
            .font(.system(size: 12))
        }
    }

    // MARK: Group cell

    private var groupOrKindOpenTitle: String {
        if item.isGroup { return "Open Group" }
        return item.kind == .disk ? "Open Disk" : "Open"
    }

    @ViewBuilder
    private var groupCell: some View {
        if layout == .grid {
            VStack(spacing: 5) {
                groupPreview
                Text(item.displayName.isEmpty ? "Group" : item.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: iconSize + 28)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill")
                    .resizable()
                    .frame(width: Self.listIconSize, height: Self.listIconSize)
                    .foregroundStyle(.secondary)
                Text(item.displayName.isEmpty ? "Group" : item.displayName)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                metaColumn("\(item.children.count) items", width: 96, alignment: .trailing)
            }
            .font(.system(size: 12))
        }
    }

    /// An iOS-folder-style mini preview: up to four child icons on a rounded, tinted
    /// tile the same footprint as a normal grid icon.
    private var groupPreview: some View {
        let tile = effectiveIconSize
        let inner = tile * 0.36
        let gap = tile * 0.08
        return RoundedRectangle(cornerRadius: tile * 0.22)
            .fill(.white.opacity(0.16))
            .frame(width: tile, height: tile)
            .overlay {
                VStack(spacing: gap) {
                    HStack(spacing: gap) { previewSlot(0, inner); previewSlot(1, inner) }
                    HStack(spacing: gap) { previewSlot(2, inner); previewSlot(3, inner) }
                }
            }
    }

    @ViewBuilder
    private func previewSlot(_ index: Int, _ size: CGFloat) -> some View {
        if groupPreviewItemID == item.id, index < groupPreviewIcons.count {
            Image(nsImage: groupPreviewIcons[index])
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }

    /// One metadata column: secondary-colored, fixed width, single line.
    private func metaColumn(_ text: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: alignment)
    }

    /// A Finder-style date for the list's date column: "Today at 9:03 PM", or
    /// "18 Feb 2026 at 18:22" (locale-aware, with relative day names for recent dates).
    static func listDate(_ date: Date) -> String { listDateFormatter.string(from: date) }

    /// The item's size for the list's size column ("2.2 MB", "811 KB").
    static func listSize(_ bytes: Int64) -> String { sizeFormatter.string(fromByteCount: bytes) }

    private static let listDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true   // "Today" / "Yesterday" where it applies
        return formatter
    }()

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private var iconImage: some View {
        // Render from the cached icon; until `.task` resolves it (one frame), show a
        // transparent placeholder rather than doing synchronous disk I/O in `body`.
        Image(nsImage: icon ?? ItemView.placeholder)
            .resizable()
            .interpolation(.high)
            .frame(width: effectiveIconSize, height: effectiveIconSize)
            .overlay(alignment: .bottom) { runningDot }
            .overlay(alignment: .topTrailing) { trashBadge }
            .overlay { ejectingSpinner }
            .overlay { sparkleOverlay }
    }

    /// A small red count badge on the Trash icon (grid only — a 16 pt list glyph is
    /// too small for it). Shares the full/empty icon's `.DS_Store`-counting caveat.
    @ViewBuilder
    private var trashBadge: some View {
        if item.kind == .trash, trashCount > 0, layout == .grid {
            Text("\(trashCount)")
                .font(.system(size: max(7, effectiveIconSize * 0.22), weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, max(3, effectiveIconSize * 0.06))
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.red))
                .fixedSize()
                .offset(x: effectiveIconSize * 0.18, y: -effectiveIconSize * 0.12)
        }
    }

    /// A dimming spinner over a disk icon while it's being ejected (Eject All).
    @ViewBuilder
    private var ejectingSpinner: some View {
        if isEjecting {
            ZStack {
                Color.black.opacity(0.3)
                ProgressView().controlSize(.small)
            }
            .frame(width: effectiveIconSize, height: effectiveIconSize)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    /// A one-shot sparkle that fades out over a newly-arrived Fresh item's icon.
    @ViewBuilder
    private var sparkleOverlay: some View {
        if sparkle {
            Image(systemName: "sparkles")
                .font(.system(size: effectiveIconSize * 0.55))
                .foregroundStyle(.yellow)
                .shadow(color: .yellow.opacity(0.7), radius: 3)
                .opacity(sparkleOpacity)
                .allowsHitTesting(false)
                .onAppear {
                    sparkleOpacity = 0.9
                    withAnimation(.easeOut(duration: 1.3)) { sparkleOpacity = 0 }
                }
        }
    }

    /// A small green dot on the bottom edge of a **running** app's icon (Dock-style).
    @ViewBuilder
    private var runningDot: some View {
        if isAppRunning {
            let dot = max(4, effectiveIconSize * 0.12)
            Circle()
                .fill(Color.green)
                .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
                .frame(width: dot, height: dot)
                .offset(y: -dot * 0.3)   // mostly inside the icon's lower edge
                .shadow(color: .black.opacity(0.3), radius: 0.5)
        }
    }

    /// Whether this item is a running application (its bundle id is in the live set).
    private var isAppRunning: Bool {
        guard item.kind == .application, let bundleID else { return false }
        return runningBundleIDs.contains(bundleID)
    }

    /// An application item's bundle identifier (read off the render path), or `nil`.
    private static func appBundleID(_ item: DrawerItem) -> String? {
        guard item.kind == .application, let url = BookmarkResolver.url(for: item) else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    /// The item's byte size and localized kind ("ZIP archive", "Folder", …) for the
    /// list columns, read off the render path. Size is `nil` for folders / non-file
    /// items (where a single number is meaningless); kind comes from the filesystem.
    private static func resolveMetadata(_ item: DrawerItem) -> (size: Int64?, kind: String?) {
        guard let url = BookmarkResolver.url(for: item) else { return (nil, nil) }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .localizedTypeDescriptionKey])
        let isDirectory = values?.isDirectory ?? false
        let size = isDirectory ? nil : values?.fileSize.map(Int64.init)
        return (size, values?.localizedTypeDescription)
    }

    /// A 1×1 transparent image shown for the one frame before `.task` resolves the
    /// real icon (avoids a blocking `resolveIcon` in `body`).
    private static let placeholder = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { _ in true }

    // MARK: Icon resolution

    static func resolveIcon(_ item: DrawerItem) -> NSImage {
        // A group renders a child preview, not a single icon; this is only a fallback
        // (e.g. if a group ever appears where a plain icon is expected).
        if item.kind == .group { return symbol("square.grid.2x2.fill") }
        // A user-chosen icon override wins over the target's own icon.
        if let data = item.customIconBookmark,
           let resolved = BookmarkResolver.resolve(data),
           let custom = NSImage(contentsOf: resolved.url) {
            return custom
        }
        // A user-defined generated icon (base shape + color + optional SF Symbol).
        if let style = item.iconStyle {
            return IconRenderer.image(for: style)
        }
        // The Trash shows the system full / empty trash can. Handled before the
        // broken check, since a Trash item has no bookmark of its own.
        if item.kind == .trash {
            return trashIcon()
        }
        // A mounted volume shows its own drive icon. Handled before the broken check
        // so a volume that just unmounted shows a drive glyph for the instant before
        // the live listing drops it, not the broken-item triangle.
        if item.kind == .disk {
            if let url = BookmarkResolver.url(for: item), FileManager.default.fileExists(atPath: url.path) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
            return symbol("externaldrive")
        }
        // A cloud drive shows a cloud-flavored icon. Handled before the broken check
        // for the same reason as `.disk` (a provider can drop out between re-lists).
        if item.kind == .cloud {
            return cloudIcon(for: item)
        }
        if BookmarkResolver.isBroken(item) {
            return symbol("exclamationmark.triangle")
        }
        // The shared store, then the target's own un-masked artwork — both from
        // PictKit, both beneath the item's own overrides above. A dictionary lookup;
        // a miss returns nil and warms in the background, so a drawer never waits.
        if let target = TopDrawerIcons.target(for: item),
           let shared = TopDrawerIcons.shared.icon(for: target) {
            return shared
        }
        switch item.kind {
        case .url:
            // A cached favicon replaces the generic globe; the async fetch that fills
            // the cache is kicked from `ItemView`'s `.task`.
            if let url = item.url, let favicon = FaviconCache.shared.cached(for: url) { return favicon }
            return symbol("globe")
        default:
            if let url = BookmarkResolver.url(for: item) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
            return symbol("questionmark.square.dashed")
        }
    }

    /// The system Trash icon — full when the Trash holds anything, empty otherwise.
    /// Emptiness mirrors Finder across every volume's trash (see `TrashInspector`).
    private static func trashIcon() -> NSImage {
        NSImage(named: TrashInspector.trashIsEmpty() ? "NSTrashEmpty" : "NSTrashFull") ?? symbol("trash")
    }

    /// A cloud-drive's icon: the system iCloud glyph for iCloud Drive (whose raw
    /// folder otherwise reads as a generic folder), and the provider's own folder
    /// icon for third-party providers (Dropbox / Drive / OneDrive set one), falling
    /// back to a cloud glyph when the folder can't be resolved.
    private static func cloudIcon(for item: DrawerItem) -> NSImage {
        guard let url = BookmarkResolver.url(for: item),
              FileManager.default.fileExists(atPath: url.path) else {
            return symbol("cloud.fill")
        }
        if url.path.contains("com~apple~CloudDocs") { return symbol("icloud.fill") }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }
}
