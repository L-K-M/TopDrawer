import SwiftUI

/// Global appearance: drawer material/layout/sizes and tab pill sizing + default
/// color. Per-tab color is edited in the Tabs pane.
struct AppearanceView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section("Preview") {
                appearancePreview
                    .frame(height: 216)
                    .frame(maxWidth: .infinity)
            }

            Section("Drawer") {
                Picker("Translucency", selection: $preferences.drawerTranslucency) {
                    ForEach(DrawerTranslucency.allCases) { Text($0.displayName).tag($0) }
                }
                VStack(alignment: .leading) {
                    Text("Icon size: \(Int(preferences.iconSize)) pt")
                    Slider(value: $preferences.iconSize, in: 32...128, step: 4)
                }
                VStack(alignment: .leading) {
                    Text("Corner radius: \(Int(preferences.cornerRadius)) pt")
                    Slider(value: $preferences.cornerRadius, in: 0...24, step: 1)
                }
            }

            Section("Tabs") {
                Picker("Style", selection: $preferences.tabStyle) {
                    ForEach(TabStyle.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading) {
                    Text("Tab thickness: \(Int(preferences.tabThickness)) pt")
                    Slider(value: $preferences.tabThickness, in: 24...64, step: 1)
                }
                VStack(alignment: .leading) {
                    Text("Auto-fade opacity: \(Int(preferences.fadedOpacity * 100))%")
                    Slider(value: $preferences.fadedOpacity, in: 0.05...0.9, step: 0.05)
                }
                Toggle("Show tab labels", isOn: $preferences.showTabLabels)
                Text("Side tabs (left/right edges) print their name vertically, so longer names fit. Auto-fade opacity sets how faint an idle auto-fading tab gets (Tabs → When idle).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ColorPicker("Default color for new tabs", selection: defaultColorBinding, supportsOpacity: false)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var defaultColorBinding: Binding<Color> {
        Binding(
            get: { Color(hexString: preferences.defaultTabColorHex) },
            set: { preferences.defaultTabColorHex = $0.hexString }
        )
    }

    // MARK: Live preview

    /// A compact but recognizable Apps drawer that re-renders as the appearance
    /// controls change. It includes the real drawer's visual landmarks rather than
    /// reducing it to an abstract pill and three blocks.
    private var appearancePreview: some View {
        ZStack {
            previewDesktop
            VStack(spacing: 0) {
                previewTab
                    .zIndex(1)
                previewDrawer
                    .frame(maxWidth: 460)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    /// Enough wallpaper detail remains visible around and through the drawer for the
    /// three translucency levels to read immediately.
    private var previewDesktop: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.35, blue: 0.72),
                                    Color(red: 0.43, green: 0.19, blue: 0.58)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(.cyan.opacity(0.22))
                .frame(width: 180, height: 180)
                .offset(x: -190, y: 70)
            Circle()
                .fill(.pink.opacity(0.20))
                .frame(width: 150, height: 150)
                .offset(x: 210, y: -65)
            Rectangle()
                .fill(.white.opacity(0.07))
                .frame(height: 38)
                .rotationEffect(.degrees(-8))
                .offset(y: 78)
        }
    }

    private var previewTab: some View {
        let color = Color(hexString: preferences.defaultTabColorHex)
        let isClassic = preferences.tabStyle == .classic
        let shape: AnyShape = preferences.tabStyle == .classic
            ? AnyShape(ClassicTabShape(edge: .bottom))
            : AnyShape(edgeRoundedRect(edge: .bottom, radius: CGFloat(preferences.cornerRadius)))
        let thickness = max(18, CGFloat(preferences.tabThickness) * 0.52
                            * preferences.tabStyle.thicknessScale)
        return HStack(spacing: 5) {
            Image(systemName: "shippingbox.fill")
            if preferences.showTabLabels {
                Text("Apps")
                    .fixedSize()
            }
        }
        .font(.system(size: max(9, thickness * 0.34), weight: .semibold))
        .foregroundStyle(color.readableForeground)
        .padding(.horizontal, preferences.showTabLabels ? 13 : 10)
        .frame(height: thickness)
        .background {
            ZStack {
                if !isClassic {
                    VisualEffectBlur(material: .popover, blendingMode: .withinWindow)
                        .clipShape(shape)
                }
                if isClassic {
                    shape.fill(
                        LinearGradient(colors: [color, color.opacity(0.76)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                } else {
                    shape.fill(color.opacity(0.88))
                }
            }
        }
        .overlay(shape.stroke(.white.opacity(0.42), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
    }

    private var previewDrawer: some View {
        let color = Color(hexString: preferences.defaultTabColorHex)
        let shape = edgeRoundedRect(edge: .bottom, radius: CGFloat(preferences.cornerRadius))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text("Apps")
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 8)
                Text("5")
                    .foregroundStyle(.secondary)
                Image(systemName: "lock.open")
                    .foregroundStyle(.secondary)
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 9))

            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                Text("Type to filter…")
                Spacer(minLength: 0)
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))

            HStack(alignment: .top, spacing: 8) {
                ForEach(0..<5, id: \.self) { index in
                    previewItem(index)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(12)
        .frame(height: 158, alignment: .top)
        .background {
            ZStack {
                VisualEffectBlur(material: .popover, blendingMode: .withinWindow)
                Color(nsColor: .windowBackgroundColor)
                    .opacity(preferences.drawerTranslucency.backingOpacity)
                color.opacity(0.10)
            }
        }
        .clipShape(shape)
        .overlay(shape.stroke(Color.primary.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.20), radius: 5, y: 2)
    }

    private func previewItem(_ index: Int) -> some View {
        let size = 20 + (CGFloat(preferences.iconSize) - 32) / 4
        return VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(colors: previewIconColors(index),
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: previewIconSymbol(index))
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
            Text(previewItemName(index))
                .font(.system(size: 8))
                .lineLimit(1)
        }
    }

    private func previewIconColors(_ index: Int) -> [Color] {
        switch index {
        case 0: return [.orange, .pink]
        case 1: return [.blue, .cyan]
        case 2: return [.purple, .indigo]
        case 3: return [.green, .mint]
        default: return [.red, .orange]
        }
    }

    private func previewIconSymbol(_ index: Int) -> String {
        switch index {
        case 0: return "terminal.fill"
        case 1: return "safari.fill"
        case 2: return "photo.fill"
        case 3: return "folder.fill"
        default: return "music.note"
        }
    }

    private func previewItemName(_ index: Int) -> String {
        switch index {
        case 0: return "Terminal"
        case 1: return "Safari"
        case 2: return "Photos"
        case 3: return "Projects"
        default: return "Music"
        }
    }
}
