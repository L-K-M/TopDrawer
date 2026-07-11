import Foundation

extension KeyedDecodingContainer {
    /// Decodes a value leniently: a missing key, a `null`, or a value that fails
    /// to decode — most importantly an enum raw value written by a **newer**
    /// Top Drawer — yields `fallback` instead of throwing.
    ///
    /// The tab model's enum-like fields grow regularly (`TabKind` alone has
    /// gained five cases since 1.0). A plain
    /// `decodeIfPresent(TabKind.self, …) ?? .items` only defaults when the key
    /// is *missing*: an unknown raw value throws, `FailableTab` then drops the
    /// whole tab, and the next debounced save rewrites `launcher.json` without
    /// it — permanent data loss from running an older build once. Degrading the
    /// single field and keeping the record is the safer failure mode.
    func decodeLenient<T: Decodable>(_ type: T.Type, forKey key: Key, fallback: T) -> T {
        ((try? decodeIfPresent(type, forKey: key)) ?? nil) ?? fallback
    }
}

/// Decodes a single `DrawerItem` without throwing: an unreadable element yields
/// `nil` (and is filtered out) rather than failing the whole `[DrawerItem]`
/// decode — which would take the entire tab down with it. The same pattern as
/// `FailableTab`; the wrapper keeps the unkeyed container's index advancing
/// past a bad element, which a thrown error would not.
struct FailableDrawerItem: Decodable {
    let item: DrawerItem?

    init(from decoder: Decoder) throws {
        item = try? DrawerItem(from: decoder)
    }
}
