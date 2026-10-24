#if os(macOS)
import AppKit
import MarkdownEngine
import SwiftUI

/// Hosts the engine while keeping persistence, links and panel focus in Top Drawer.
@available(macOS 14, *)
struct NotesEditorNativeView: NSViewRepresentable {
    let documentID: UUID
    let markdown: String
    let formattingBar: NotesEditorFormattingBar
    let onChanged: (String, UUID) -> Void
    let onOpenLink: (URL) -> Void
    let registerFlush: (((() -> Void)?) -> Void)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.makeView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.update(self)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    final class Coordinator {
        private static let horizontalInset: CGFloat = 14

        // Give headings a clear hierarchy without shrinking below body text.
        private static let headingStyle = HeadingStyle(
            fontMultipliers: [2.4, 2.0, 1.6, 1.35, 1.15, 1.0],
            topSpacingEm: [0.6, 0.5, 0.4, 0.35, 0.3, 0.25]
        )

        private var parent: NotesEditorNativeView
        private var markdown: String
        private var hasEdits = false
        private var isTornDown = false
        private weak var host: NotesEditorNativeHostingView?
        private weak var textView: NSTextView?
        private var changeObserver: NSObjectProtocol?
        private var eventMonitor: Any?
        private var linkInteraction = NotesEditorLinkInteraction()
        private let notificationPrefix = "TopDrawer.notes.\(UUID().uuidString)"

        fileprivate init(_ parent: NotesEditorNativeView) {
            self.parent = parent
            markdown = parent.markdown
        }

        fileprivate func makeView() -> NSView {
            let view = NotesEditorNativeHostingView(rootView: content)
            host = view
            view.onLayout = { [weak self, weak view] in
                guard let view else { return }
                self?.attachTextView(in: view)
            }
            parent.registerFlush { [weak self] in self?.flush() }
            return view
        }

        fileprivate func update(_ parent: NotesEditorNativeView) {
            self.parent = parent
            if markdown != parent.markdown {
                markdown = parent.markdown
                hasEdits = false
            }
            host?.rootView = content
        }

        private var content: AnyView {
            var bus = MarkdownEditorBus()
            bus.applyBoldRequest = notification(for: .bold)
            bus.applyItalicRequest = notification(for: .italic)
            bus.applyStrikethroughRequest = notification(for: .strikethrough)
            bus.applyHeadingRequest = notification(for: .heading)
            bus.applyUnorderedListRequest = notification(for: .bullets)
            bus.applyOrderedListRequest = notification(for: .numbers)
            bus.applyBlockquoteRequest = notification(for: .quote)
            bus.applyInlineCodeRequest = notification(for: .code)

            let configuration = MarkdownEditorConfiguration(
                services: MarkdownEditorServices(bus: bus),
                headings: Self.headingStyle,
                textInsets: TextInsets(horizontal: Self.horizontalInset, vertical: 10),
                extensions: [StrikethroughExtension()]
            )
            let binding = Binding(
                get: { [self] in markdown },
                set: { [weak self] value in
                    guard let self, !isTornDown, value != markdown, let textView,
                          !textView.hasMarkedText(), value == storageText(in: textView) else { return }
                    accept(value)
                }
            )

            return AnyView(VStack(spacing: 0) {
                if parent.formattingBar == .visible {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(FormattingCommand.allCases, id: \.self) { command in
                                Button { self.apply(command) } label: {
                                    Image(systemName: command.symbol)
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                .help(command.title)
                                .accessibilityLabel(command.title)
                            }
                        }
                        .padding(.horizontal, Self.horizontalInset)
                        .padding(.vertical, 8)
                    }
                    Divider()
                }
                NativeTextViewWrapper(
                    text: binding,
                    configuration: configuration,
                    fontName: NSFont.systemFont(ofSize: NSFont.systemFontSize).fontName,
                    fontSize: NSFont.systemFontSize,
                    documentId: parent.documentID.uuidString,
                    onBuildContextMenu: { _, _ in Self.editMenu() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            })
        }

        // MARK: Editing and lifecycle

        private func attachTextView(in view: NSView) {
            guard textView == nil, let window = view.window,
                  let editor = Self.findTextView(in: view) else { return }
            textView = editor
            editor.setAccessibilityLabel("Note")
            editor.isAutomaticDataDetectionEnabled = false
            editor.isAutomaticLinkDetectionEnabled = false
            window.makeFirstResponder(editor)

            changeObserver = NotificationCenter.default.addObserver(
                forName: NSText.didChangeNotification, object: editor, queue: .main
            ) { [weak self] _ in
                guard let self, !isTornDown else { return }
                hasEdits = true
                guard !editor.hasMarkedText() else { return }
                accept(storageText(in: editor))
            }
            // shortcut: 0.14 has no URL activation hook. Keep routing local to this
            // text view until the engine exposes host-controlled link activation.
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) {
                [weak self] event in
                guard let self else { return event }
                return handle(event)
            }
        }

        private func storageText(in editor: NSTextView) -> String {
            // Display text can omit wiki-link IDs. Use the engine's storage transform.
            WikiLinkService.makeStorageState(
                from: editor.string,
                existingMetadata: WikiLinkService.makeDisplayState(from: markdown).metadata,
                textStorage: editor.textStorage
            ).storage
        }

        private func accept(_ value: String) {
            guard value != markdown else { return }
            markdown = value
            parent.onChanged(value, parent.documentID)
        }

        private func flush() {
            if let textView, hasEdits || textView.hasMarkedText() {
                textView.unmarkText()
                markdown = storageText(in: textView)
            }
            // Also acknowledge an unchanged flush so quit need not wait for its timeout.
            parent.onChanged(markdown, parent.documentID)
        }

        fileprivate func tearDown() {
            flush()
            isTornDown = true
            parent.registerFlush(nil)
            if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            changeObserver = nil
            eventMonitor = nil
        }

        // MARK: Host commands

        private func notification(for command: FormattingCommand) -> Notification.Name {
            Notification.Name("\(notificationPrefix).\(command.rawValue)")
        }

        private func apply(_ command: FormattingCommand) {
            guard let textView, !textView.hasMarkedText() else { return }
            textView.window?.makeFirstResponder(textView)
            NotificationCenter.default.post(name: notification(for: command), object: nil,
                                            userInfo: command == .heading ? ["level": 2] : nil)
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let textView, event.window === textView.window else { return event }
            // Caps Lock lives in .deviceIndependentFlagsMask but must not gate the
            // formatting shortcuts: without subtracting it, ⇪⌘B silently dead-keys.
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
            if event.type == .keyDown {
                guard textView.window?.firstResponder === textView, modifiers == .command else { return event }
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "b": apply(.bold)
                case "i": apply(.italic)
                default: return event
                }
                return nil
            }

            let point = textView.convert(event.locationInWindow, from: nil)
            guard textView.visibleRect.contains(point), let storage = textView.textStorage else { return event }
            let insertion = textView.characterIndexForInsertion(at: point)
            let activation: NotesEditorLinkInteraction.Activation =
                modifiers.intersection([.command, .control]).isEmpty ? .edit : .open
            if let url = linkInteraction.activate(at: insertion, in: storage, as: activation) {
                parent.onOpenLink(url)
                return nil
            }
            // Keep the original gesture for native drag, word and Shift selection.
            return event
        }

        private static func findTextView(in view: NSView) -> NSTextView? {
            if let textView = view as? NSTextView { return textView }
            return view.subviews.lazy.compactMap { findTextView(in: $0) }.first
        }

        private static func editMenu() -> NSMenu {
            // AppKit's default link menu can bypass the host's URL policy.
            let menu = NSMenu()
            for (title, action) in [("Cut", #selector(NSText.cut(_:))),
                                    ("Copy", #selector(NSText.copy(_:))),
                                    ("Paste", #selector(NSText.paste(_:))),
                                    ("Select All", #selector(NSText.selectAll(_:)))] {
                menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            }
            return menu
        }
    }

    private enum FormattingCommand: String, CaseIterable {
        case bold, italic, strikethrough, heading, bullets, numbers, quote, code

        var title: String {
            switch self {
            case .bold: return "Bold (⌘B)"
            case .italic: return "Italic (⌘I)"
            case .strikethrough: return "Strikethrough"
            case .heading: return "Heading 2"
            case .bullets: return "Bullet list"
            case .numbers: return "Numbered list"
            case .quote: return "Block quote"
            case .code: return "Inline code"
            }
        }

        var symbol: String {
            switch self {
            case .bold: return "bold"
            case .italic: return "italic"
            case .strikethrough: return "strikethrough"
            case .heading: return "textformat.size"
            case .bullets: return "list.bullet"
            case .numbers: return "list.number"
            case .quote: return "text.quote"
            case .code: return "chevron.left.forwardslash.chevron.right"
            }
        }
    }
}

@available(macOS 14, *)
private final class NotesEditorNativeHostingView: NSHostingView<AnyView> {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}
#endif
