#if os(Linux) && canImport(CGtk4)
import CGtk4
import Foundation

// The GTK interop layer — the only file family allowed to know that GTK is a C API.
// Shapes are the dexbar-proven ones (a shipped Swift GTK4 app): signals through
// `g_signal_connect_data` (the non-variadic variant — so no C shim is needed for the
// varargs `g_signal_connect`), closures boxed with Unmanaged and released by a
// GDestroyNotify. GTK4's headers mix complete instance structs (GtkWidget, GtkLabel,
// GtkWindow — imported as UnsafeMutablePointer<T>) with opaque ones (the event
// controllers — imported as OpaquePointer), so every helper comes in both flavors.

typealias GWidget = UnsafeMutablePointer<GtkWidget>
typealias GWindow = UnsafeMutablePointer<GtkWindow>
typealias GBox = UnsafeMutablePointer<GtkBox>

func asWindow(_ widget: GWidget?) -> GWindow? { widget.flatMap { GWindow(OpaquePointer($0)) } }
func asBox(_ widget: GWidget?) -> GBox? { widget.flatMap { GBox(OpaquePointer($0)) } }
/// A typed child (label, …) re-wrapped as the GtkWidget* the container API wants.
func asWidget<P>(_ child: UnsafeMutablePointer<P>?) -> GWidget? {
    child.map { UnsafeMutablePointer<GtkWidget>(OpaquePointer($0)) }
}

/// Opaque-child flavor (the label's accessors take OpaquePointer even though its
/// constructor hands back a typed pointer — GTK4's mixed import modes).
func asWidget(_ child: OpaquePointer?) -> GWidget? {
    child.map { UnsafeMutablePointer<GtkWidget>($0) }
}

// MARK: - Signals

/// A Swift closure boxed for C: the signal's user-data pointer.
final class GtkCallback {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
}

/// A Swift closure taking event coordinates, boxed for C the same way.
final class GtkCoordinateCallback {
    let action: (Double, Double) -> Void
    init(_ action: @escaping (Double, Double) -> Void) { self.action = action }
}

private func gtkConnectRaw(_ instance: UnsafeMutableRawPointer?, signal: String,
                           trampoline: GCallback, box: gpointer?,
                           destroy: GClosureNotify?) {
    g_signal_connect_data(instance, signal, trampoline, box, destroy,
                          GConnectFlags(rawValue: 0))
}

// g_signal_connect_data's destroy callback is a GClosureNotify — (data, closure) —
// not a GDestroyNotify; the closure pointer is of no interest here.
private let gtkCallbackDestroy: GClosureNotify? = { data, _ in
    guard let data else { return }
    Unmanaged<GtkCallback>.fromOpaque(data).release()
}

private let gtkCoordinateCallbackDestroy: GClosureNotify? = { data, _ in
    guard let data else { return }
    Unmanaged<GtkCoordinateCallback>.fromOpaque(data).release()
}

/// Connects an argumentless signal (`leave`, `close-request`, …) to a closure —
/// typed-pointer instance flavor (callers that already hold an opaque controller
/// pointer use the OpaquePointer overload).
func gtkConnect<P>(_ instance: UnsafeMutablePointer<P>?, signal: String,
                   _ action: @escaping () -> Void) {
    gtkConnectRaw(instance.map { UnsafeMutableRawPointer($0) }, signal: signal,
                  trampoline: unsafeBitCast(noArgTrampoline, to: GCallback.self),
                  box: Unmanaged.passRetained(GtkCallback(action)).toOpaque(),
                  destroy: gtkCallbackDestroy)
}

/// Opaque-instance flavor (event controllers and friends).
func gtkConnect(_ instance: OpaquePointer?, signal: String,
                _ action: @escaping () -> Void) {
    gtkConnectRaw(instance.map { UnsafeMutableRawPointer($0) }, signal: signal,
                  trampoline: unsafeBitCast(noArgTrampoline, to: GCallback.self),
                  box: Unmanaged.passRetained(GtkCallback(action)).toOpaque(),
                  destroy: gtkCallbackDestroy)
}

private let noArgTrampoline: @convention(c) (OpaquePointer?, gpointer?) -> Void = { _, data in
    guard let data else { return }
    Unmanaged<GtkCallback>.fromOpaque(data).takeUnretainedValue().action()
}

/// `close-request` on a GtkWindow: (window, user_data) -> gboolean. Returning FALSE
/// lets GTK's default close handling run — a void trampoline here would leave the
/// return register undefined (calling through a mismatched prototype is UB, and a
/// garbage TRUE would stop the default handler).
func gtkConnectCloseRequest<P>(_ window: UnsafeMutablePointer<P>?,
                               _ action: @escaping () -> Void) {
    gtkConnectRaw(window.map { UnsafeMutableRawPointer($0) }, signal: "close-request",
                  trampoline: unsafeBitCast(closeRequestTrampoline, to: GCallback.self),
                  box: Unmanaged.passRetained(GtkCallback(action)).toOpaque(),
                  destroy: gtkCallbackDestroy)
}

private let closeRequestTrampoline: @convention(c) (OpaquePointer?, gpointer?) -> gboolean = { _, data in
    if let data { Unmanaged<GtkCallback>.fromOpaque(data).takeUnretainedValue().action() }
    return 0
}

/// `enter` on a GtkEventControllerMotion: (controller, x, y, user_data).
func gtkConnectEnter(_ controller: OpaquePointer?,
                     _ action: @escaping (Double, Double) -> Void) {
    gtkConnectRaw(controller.map { UnsafeMutableRawPointer($0) }, signal: "enter",
                  trampoline: unsafeBitCast(enterTrampoline, to: GCallback.self),
                  box: Unmanaged.passRetained(GtkCoordinateCallback(action)).toOpaque(),
                  destroy: gtkCoordinateCallbackDestroy)
}

private let enterTrampoline: @convention(c) (OpaquePointer?, Double, Double, gpointer?) -> Void = { _, x, y, data in
    guard let data else { return }
    Unmanaged<GtkCoordinateCallback>.fromOpaque(data).takeUnretainedValue().action(x, y)
}

/// `released` on a GtkGestureClick: (gesture, n_press, x, y, user_data).
func gtkConnectClickReleased(_ controller: OpaquePointer?,
                             _ action: @escaping (Double, Double) -> Void) {
    gtkConnectRaw(controller.map { UnsafeMutableRawPointer($0) }, signal: "released",
                  trampoline: unsafeBitCast(clickReleasedTrampoline, to: GCallback.self),
                  box: Unmanaged.passRetained(GtkCoordinateCallback(action)).toOpaque(),
                  destroy: gtkCoordinateCallbackDestroy)
}

private let clickReleasedTrampoline: @convention(c) (OpaquePointer?, gint, Double, Double, gpointer?) -> Void = { _, _, x, y, data in
    guard let data else { return }
    Unmanaged<GtkCoordinateCallback>.fromOpaque(data).takeUnretainedValue().action(x, y)
}

// MARK: - Main-thread marshalling

/// Runs `action` on the GLib main loop (the GTK thread). Safe from any thread; the
/// box is freed by the source's destroy notify whether or not the source fires.
func onMainLoop(_ action: @escaping @Sendable () -> Void) {
    final class IdleBox {
        let action: @Sendable () -> Void
        init(_ action: @escaping @Sendable () -> Void) { self.action = action }
    }

    let fire: @convention(c) (gpointer?) -> gboolean = { data in
        guard let data else { return 0 }
        Unmanaged<IdleBox>.fromOpaque(data).takeUnretainedValue().action()
        return 0   // one-shot
    }
    let destroy: GDestroyNotify? = { data in
        guard let data else { return }
        Unmanaged<IdleBox>.fromOpaque(data).release()
    }

    // 200 == G_PRIORITY_DEFAULT_IDLE (glib's macro isn't imported by name).
    g_idle_add_full(200, fire, Unmanaged.passRetained(IdleBox(action)).toOpaque(), destroy)
}
#endif
