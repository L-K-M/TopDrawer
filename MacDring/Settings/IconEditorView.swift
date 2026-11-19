import LiveryKit
import SwiftUI

/// Editor for an item's **generated** icon — base shape + color + optional SF Symbol
/// — with a live preview. Reports the chosen `IconStyle`, or `nil` to clear it (back
/// to the item's default icon). Presented by `IconEditorWindowController`.
struct IconEditorView: View {
    let itemName: String
    let onSave: (IconStyle?) -> Void
    let onCancel: () -> Void

    @State private var base: IconStyle.Base
    @State private var colorHex: String
    @State private var symbol: String   // "" = no symbol

    init(itemName: String,
         initial: IconStyle?,
         onSave: @escaping (IconStyle?) -> Void,
         onCancel: @escaping () -> Void) {
        self.itemName = itemName
        self.onSave = onSave
        self.onCancel = onCancel
        _base = State(initialValue: initial?.base ?? .folder)
        _colorHex = State(initialValue: initial?.colorHex ?? "#0A84FF")
        _symbol = State(initialValue: initial?.symbol ?? "")
    }

    private var draft: IconStyle {
        IconStyle(base: base, colorHex: colorHex, symbol: symbol.isEmpty ? nil : symbol)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Customize Icon").font(.headline)
                Text(itemName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }

            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: IconRenderer.image(for: draft, pointSize: 128))
                    .resizable().interpolation(.high)
                    .frame(width: 84, height: 84)
                    .accessibilityLabel("Icon preview")

                Form {
                    Picker("Base", selection: $base) {
                        ForEach(IconStyle.Base.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    ColorSwatchPicker(title: "Color", hex: $colorHex)
                    LabeledContent("Symbol") {
                        HStack(spacing: 6) {
                            SymbolPickerView(symbolName: $symbol)
                            if !symbol.isEmpty {
                                Button { symbol = "" } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .help("Remove symbol")
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }

            HStack {
                Button("Use Default", role: .destructive) { onSave(nil) }
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save") { onSave(draft) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
