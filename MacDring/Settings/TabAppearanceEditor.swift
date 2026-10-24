import SwiftUI

struct TabAppearanceEditor: View {
    @Binding var appearance: DrawerAppearance
    let kind: TabKind

    var body: some View {
        Section("Appearance") {
            Picker("Visual preset", selection: $appearance.preset) {
                ForEach(DrawerAppearance.Preset.allCases) { Text($0.displayName).tag($0) }
            }
            if kind != .notes && kind != .clipboard {
                Picker("Item titles", selection: $appearance.titleVisibility) {
                    ForEach(DrawerAppearance.TitleVisibility.allCases) { Text($0.displayName).tag($0) }
                }
                Stepper("Item text: \(Int(appearance.itemFontSize)) pt", value: $appearance.itemFontSize,
                        in: DrawerAppearance.fontSizeRange)
                Picker("Item text weight", selection: $appearance.itemFontWeight) {
                    ForEach(DrawerAppearance.FontWeight.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("File extensions", selection: $appearance.fileExtensions) {
                    ForEach(DrawerAppearance.FileExtensions.allCases) { Text($0.displayName).tag($0) }
                }
                Text("Hidden titles remain available as tooltips and accessibility labels. Custom names are preserved.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Stepper("Tab text: \(Int(appearance.tabFontSize)) pt", value: $appearance.tabFontSize,
                    in: DrawerAppearance.fontSizeRange)
            Picker("Tab text weight", selection: $appearance.tabFontWeight) {
                ForEach(DrawerAppearance.FontWeight.allCases) { Text($0.displayName).tag($0) }
            }
            Button("Reset Appearance") { appearance = DrawerAppearance() }
        }
    }
}
