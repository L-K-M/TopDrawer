#if os(Linux) && canImport(CGtk4)
import CGtk4
import Foundation

// The GTK interop layer — the only file family allowed to know that GTK is a C API.
// Shapes are the dexbar-proven ones (a shipped Swift GTK4 app): GObject casts via
// OpaquePointer, signals through `g_signal_connect_data` (the non-variadic variant —
// so no C shim is needed for the varargs `g_signal_connect`), closures boxed with
// Unmanaged and released by a GDestroyNotify.

typealias GWidget = UnsafeMutablePointer<GtkWidget>
typealias GWindow = UnsafeMutablePointer<GtkWindow>
typealias GBox = UnsafeMutablePointer<GtkBox>
/// GTK4 keeps GtkLabel's instance struct private — the C API hands out pointers
/// without a complete type, which the importer surfaces as OpaquePointer.
typealias GLabel = OpaquePointer

func asWindow(_ widget: GWidget?) -> GWindow? { widget.flatMap { GWindow(OpaquePointer($0)) } }
func asBox(_ widget: GWidget?) -> GBox? { widget.flatMap { GBox(OpaquePointer($0)) } }
/// An opaque child (e.g. a label) re-wrapped as the GtkWidget* the container API wants.
func asWidget(_ child: OpaquePointer?) -> GWidget? { child.map { UnsafeMutablePointer<GtkWidget>($0) } }

// MARK: - Signals

/// A Swift closure boxed for C: the signal's user-data pointer.
final class GtkCallback {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
}

private let gtkCallbackDestroy: GDestroyNotify? = { data in
    guard let data else { return }
    Unmanaged<GtkCallback>.fromOpaque(data).release()
}

private func gtkConnect(_ instance: OpaquePointer?, signal: String,
                        trampoline: GCallback, action: @escaping () -> Void) {
    g_signal_connect_data(
        controller.map { UnsafeMutableRawPointer($0) }, signal,
        trampoline, Unmanaged.passRetained(GtkCallback(action)).toOpaque(),
        gtkCallbackDestroy, GConnectFlags(rawValue: 0))
}

/// Connects an argumentless signal (`leave`, `close-request`, …) to a closure.
func gtkConnect(_ instance: OpaquePointer?, signal: String, _ action: @escaping () -> Void) {
    gtkConnect(instance, signal: signal,
               trampoline: unsafeBitCast(noArgTrampoline, to: GCallback.self), action: action)
}

private let noArgTrampoline: @convention(c) (OpaquePointer?, gpointer?) -> Void = { _, data in
    guard let data else { return }
    Unmanaged<GtkCallback>.fromOpaque(data).takeUnretainedValue().action()
}

/// `enter` on a GtkEventControllerMotion: (controller, x, y, user_data).
func gtkConnectEnter(_ controller: OpaquePointer?, _ action: @escaping (Double, Double) -> Void) {
    final class Box2 {
        let action: (Double, Double) -> Void
        init(_ action: @escaping (Double, Double) -> Void) { self.action = action }
    }
    let trampoline: @convention(c) (OpaquePointer?, Double, Double, gpointer?) -> Void = { _, x, y, data in
        guard let data else { return }
        Unmanaged<Box2>.fromOpaque(data).takeUnretainedValue().action(x, y)
    }
    g_signal_connect_data(
        controller.map { UnsafeMutableRawPointer($0) }, "enter",
        unsafeBitCast(trampoline, to: GCallback.self),
        Unmanaged.passRetained(Box2(action)).toOpaque(),
        { data in if let data { Unmanaged<Box2>.fromOpaque(data).release() } },
        GConnectFlags(rawValue: 0))
}

/// `released` on a GtkGestureClick: (gesture, n_press, x, y, user_data).
func gtkConnectClickReleased(_ controller: OpaquePointer?, _ action: @escaping (Double, Double) -> Void) {
    gtkConnectCoordinates(controller, signal: "released", action)
}

/// Connects any (source, Double, Double, user_data)-shaped signal — click and motion
/// controllers share it.
private func gtkConnectCoordinates(_ instance: OpaquePointer?, signal: String,
                                   _ action: @escaping (Double, Double) -> Void) {
    gtkConnect(instance, signal: signal,
               trampoline: unsafeBitCast(coordinateTrampoline, to: GCallback.self), action: action)
}

private let coordinateTrampoline: @convention(c) (OpaquePointer?, gint, Double, Double, gpointer?) -> Void = { _, _, x, y, data in
    guard let data else { return }
    Unmanaged<GtkCallback>.fromOpaque(data).takeUnretainedValue().action(x, y)
}

// MARK: - Main-thread marshalling

/// Runs `action` on the GLib main loop (the GTK thread). Safe from any thread; the
/// box is freed by the source's destroy notify whether or not the source fires.
func onMainLoop(_ action: @escaping () -> Void) {
    final class IdleBox {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
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
