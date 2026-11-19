import SwiftUI
import LiveryKit

/// A color row for Settings and the New Tab and icon editors: the curated
/// `TabPalette` swatches for one-click choices, then the system color well for
/// anything else. The chosen swatch wears a ring; a custom color leaves all bare.
struct ColorSwatchPicker: View {
    let title: String
    @Binding var hex: String

    private static let swatchSize: CGFloat = 16

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                let selected = TabPalette.swatch(matching: hex)
                ForEach(TabPalette.swatches, id: \.hex) { swatch in
                    swatchButton(swatch, isSelected: swatch == selected)
                }
                ColorPicker("Custom color", selection: customBinding, supportsOpacity: false)
                    .labelsHidden()
                    .help("Choose any color")
                    .padding(.leading, 2)
            }
        }
    }

    private func swatchButton(_ swatch: TabPalette.Swatch, isSelected: Bool) -> some View {
        Button { hex = swatch.hex } label: {
            Circle()
                .fill(Color(hexString: swatch.hex))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                .frame(width: Self.swatchSize, height: Self.swatchSize)
                .padding(2)
                .overlay(Circle().strokeBorder(isSelected ? Color.primary.opacity(0.75) : .clear, lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(swatch.name)
        .accessibilityLabel(swatch.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var customBinding: Binding<Color> {
        Binding(get: { Color(hexString: hex) }, set: { hex = $0.hexString })
    }
}
