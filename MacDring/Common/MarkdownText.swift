import SwiftUI

/// A lightweight Markdown renderer for the notes tab's **preview** mode. Handles the
/// "basic" Markdown a quick note uses: ATX headings (`#`–`###`), bullet lists
/// (`-`/`*`), and inline emphasis / code / links (via `AttributedString`). Block
/// parsing is line-based and **pure** (`classify`) so it's unit-testable; full
/// CommonMark (nested lists, tables, code fences, blockquotes, …) is out of scope.
struct MarkdownText: View {
    let text: String
    /// Called with a line index when its `- [ ]` / `- [x]` checkbox is tapped, so a
    /// notes preview can rewrite the source. `nil` (the default) renders read-only.
    var onToggle: ((Int) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(MarkdownText.lines(text).enumerated()), id: \.offset) { index, raw in
                view(for: MarkdownText.classify(raw), index: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for line: Line, index: Int) -> some View {
        switch line {
        case .blank:
            Color.clear.frame(height: 4)
        case .heading(let level, let text):
            inline(text).font(MarkdownText.headingFont(level)).bold()
        case .checkbox(let isChecked, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button { onToggle?(index) } label: {
                    Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isChecked ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(onToggle == nil)
                inline(text)
                    .strikethrough(isChecked, color: .secondary)
                    .foregroundStyle(isChecked ? .secondary : .primary)
            }
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                inline(text)
            }
        case .paragraph(let text):
            inline(text)
        }
    }

    /// Inline emphasis / code / links via `AttributedString`; plain text on failure.
    private func inline(_ string: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(string)
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        default: return .headline
        }
    }

    // MARK: Pure line splitting & classification

    /// Splits note text into lines with **normalized** endings: CRLF, bare CR, and
    /// the Unicode line/paragraph separators each count as exactly one break.
    /// Shared by the renderer and `togglingCheckbox` so their line indexes always
    /// agree. (Splitting on `CharacterSet.newlines` treated CRLF as *two* breaks,
    /// so toggling a checkbox in pasted Windows-style text rejoined with an extra
    /// phantom blank line per line ending.) Pure, so it's unit-testable.
    static func lines(_ text: String) -> [String] {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        for separator in ["\r", "\u{2028}", "\u{2029}"] {
            normalized = normalized.replacingOccurrences(of: separator, with: "\n")
        }
        return normalized.components(separatedBy: "\n")
    }

    enum Line: Equatable {
        case blank
        case heading(level: Int, text: String)
        case checkbox(isChecked: Bool, text: String)
        case bullet(text: String)
        case paragraph(text: String)
    }

    /// Classifies one line of Markdown. Pure, so it's unit-testable independently of
    /// the (hard-to-assert) inline `AttributedString` rendering.
    static func classify(_ raw: String) -> Line {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .blank }
        // ATX heading: 1–6 leading '#' followed by a space (rendered at up to 3 sizes).
        if trimmed.hasPrefix("#") {
            var level = 0
            var rest = Substring(trimmed)
            while rest.first == "#" { level += 1; rest = rest.dropFirst() }
            if level <= 6, rest.first == " " {
                return .heading(level: min(level, 3), text: String(rest).trimmingCharacters(in: .whitespaces))
            }
        }
        // Checkbox item: '- [ ] text' (unchecked) or '- [x] text' (checked) — must be
        // tested before the plain bullet, which also starts with '- '.
        if trimmed.hasPrefix("- [") {
            let body = trimmed.dropFirst(2)   // drop the "- "
            if body.count >= 3, body.first == "[",
               body[body.index(body.startIndex, offsetBy: 2)] == "]" {
                let mark = body[body.index(after: body.startIndex)]
                let rest = String(body.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if mark == " " { return .checkbox(isChecked: false, text: rest) }
                if mark == "x" || mark == "X" { return .checkbox(isChecked: true, text: rest) }
            }
        }
        // Bullet list item: '- ' or '* '.
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            return .bullet(text: String(trimmed.dropFirst(2)))
        }
        return .paragraph(text: raw)
    }

    /// Flips the checkbox marker on line `lineIndex` of `text` (`[ ]`↔`[x]`),
    /// returning the rewritten source. A no-op if that line isn't a checkbox. Uses
    /// the same `lines(_:)` split as the renderer, so the tapped index always names
    /// the same line (the rewrite normalizes any CRLF/CR endings to `\n`). Pure.
    static func togglingCheckbox(in text: String, lineIndex: Int) -> String {
        var lines = MarkdownText.lines(text)
        guard lines.indices.contains(lineIndex),
              case .checkbox(let isChecked, _) = classify(lines[lineIndex]) else { return text }
        let line = lines[lineIndex]
        if isChecked, let r = line.range(of: "[x]", options: .caseInsensitive) {
            lines[lineIndex] = line.replacingCharacters(in: r, with: "[ ]")
        } else if !isChecked, let r = line.range(of: "[ ]") {
            lines[lineIndex] = line.replacingCharacters(in: r, with: "[x]")
        }
        return lines.joined(separator: "\n")
    }
}
