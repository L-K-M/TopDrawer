import Foundation

/// A UI icon identified by its SF Symbol name — the form stored in `TabGlyph` and
/// `IconStyle` and referenced throughout the app. Resolving it yields the name to
/// actually render: the SF Symbol name on macOS (rendering unchanged), or the mapped
/// icon in the chosen Linux set on Linux. Storage keeps the SF names, so there is **no
/// document migration** — only rendering goes through the resolver. See PLAN.md §LP-13.
struct IconName: Equatable {
    /// The SF Symbol name as stored/authored (e.g. "folder.fill").
    let sfSymbol: String

    init(sfSymbol: String) { self.sfSymbol = sfSymbol }

    /// The platform an icon name is resolved for.
    enum Platform {
        case macOS, linux

        /// The platform this build renders for — so a call site can resolve without
        /// hard-coding one (`.resolved(for: .current)`). The port targets macOS and Linux
        /// only; a third platform compiling this file fails loudly rather than silently
        /// feeding Lucide names into an SF Symbol path.
        static var current: Platform {
            #if os(macOS)
            return .macOS
            #elseif os(Linux)
            return .linux
            #else
            #error("IconName.Platform.current supports only macOS and Linux")
            #endif
        }
    }

    /// The generic glyph used on Linux when the chosen set has no mapping for a symbol.
    /// A Lucide name that always exists, so an unmapped symbol still renders something.
    static let genericLinuxIcon = "square"

    /// The icon name to render on `platform`. macOS renders the stored SF name unchanged;
    /// Linux maps it through `IconMap.linux` (a Lucide name), falling back to the generic
    /// glyph for an unmapped symbol.
    func resolved(for platform: Platform) -> String {
        switch platform {
        case .macOS:
            return sfSymbol
        case .linux:
            return IconMap.linux[sfSymbol] ?? Self.genericLinuxIcon
        }
    }

    /// Whether the Linux set has a specific mapping for this symbol. `false` means
    /// `resolved(for: .linux)` would use the generic fallback — the signal a Linux
    /// renderer uses to log an unmapped symbol once.
    var hasLinuxMapping: Bool { IconMap.linux[sfSymbol] != nil }
}
