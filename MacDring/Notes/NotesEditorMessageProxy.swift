#if os(macOS)
import Foundation
import WebKit

/// Forwards script messages to a weakly held delegate.
///
/// `WKUserContentController` retains the handlers added to it, and the object that
/// wants the messages (the web view's coordinator) owns the web view — so a
/// direct handler registration is a retain cycle that keeps the whole editor
/// alive for the life of the app. The proxy breaks it: the controller retains the
/// proxy, the proxy holds the coordinator weakly, and the coordinator stays owned
/// by SwiftUI.
final class NotesEditorMessageProxy: NSObject, WKScriptMessageHandler {

    /// Name this proxy was registered under, checked against the protocol so a
    /// stray sender cannot borrow the channel.
    private let expectedName: String
    private weak var delegate: WKScriptMessageHandler?

    init(name: String = NotesEditorProtocol.messageHandlerName, delegate: WKScriptMessageHandler) {
        self.expectedName = name
        self.delegate = delegate
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == expectedName else { return }
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
#endif
