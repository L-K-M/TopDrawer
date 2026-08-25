import SwiftUI

/// A button that opens a searchable popover grid of SF Symbols to choose a tab
/// glyph from — so the user picks visually rather than typing a symbol name.
///
/// SF Symbols has thousands of symbols, but there's no public API to enumerate
/// them, so this offers a large curated set plus a name search.
struct SymbolPickerView: View {
    @Binding var symbolName: String
    @State private var showing = false
    @State private var search = ""

    private var filtered: [String] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return SymbolPickerView.symbols }
        return SymbolPickerView.symbols.filter { $0.contains(query) }
    }

    var body: some View {
        Button {
            showing = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbolName.isEmpty ? "questionmark.square.dashed" : symbolName)
                    .frame(width: 18)
                Text("Choose Symbol…")
            }
        }
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(spacing: 10) {
                TextField("Search symbols", text: $search)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                        ForEach(filtered, id: \.self) { name in
                            Button {
                                symbolName = name
                                showing = false
                            } label: {
                                Image(systemName: name)
                                    .font(.system(size: 17))
                                    .frame(width: 30, height: 30)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(name == symbolName ? Color.accentColor.opacity(0.30) : .clear)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(name)
                        }
                    }
                    if filtered.isEmpty {
                        Text("No symbols match “\(search)”.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                    }
                }
            }
            .padding(14)
            .frame(width: 360, height: 360)
        }
    }

    /// The curated SF Symbols offered as tab glyphs. Extracted to the platform-neutral
    /// `CuratedSymbols` (LP-13) so the icon layer and its mapping-completeness test reach
    /// the same list.
    static let symbols = CuratedSymbols.all
}
