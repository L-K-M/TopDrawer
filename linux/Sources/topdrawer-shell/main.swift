// topdrawer-shell — the LP-20 "hello dock": one anchored, undecorated strip rendered
// through GTK4 + gtk4-layer-shell, logging pointer enter/leave and clicks, with its
// content (the tab titles) read from topdrawerd over D-Bus.
//
// Manual verification notes (CI has no compositor, so it only builds this): under a
// layer-shell compositor (KDE Plasma 6, sway, hyprland, COSMIC, …) the strip appears
// anchored to the configured edge, above normal windows, reserving no screen space.
// On GNOME or X11 it exits at startup with the "not a layer-shell compositor" error
// from gtk_layer_is_supported — the GNOME frontend is the LP-27 extension instead.

#if os(Linux) && canImport(CGtk4) && canImport(CGtkLayerShell)
import CGtk4
import CGtkLayerShell
import DBUS
import Foundation
import Logging
import TopDrawerShell
import TopDrawerVersion

// `--version` / `--help` answer before gtk_init: the Debian package's install smoke test
// runs `topdrawer-shell --version` headless (no display, no compositor, no bus) — which
// also proves the vendored gtk4-layer-shell library resolves, since the loader maps every
// linked library before `main` runs.
CommandLineFlags.exitOnVersionOrHelp(
    program: "topdrawer-shell",
    usage: """
        usage: topdrawer-shell [--edge top|bottom|left|right] [--monitor N] [--version] [--help]

        Top Drawer's layer-shell frontend: a dock strip anchored to one screen edge.
        Needs a compositor implementing wlr-layer-shell (KDE Plasma 6, sway, hyprland,
        COSMIC, …) and a running topdrawerd. On GNOME or X11 it exits with an error.
        """)

/// The screen edge the strip anchors to. An enum, not a bool — the CLI maps straight
/// onto it and LP-21's per-tab placement reuses it.
enum DockEdge: String {
    case top, bottom, left, right

    static func fromArguments(_ args: [String]) -> DockEdge? {
        guard let flag = args.firstIndex(of: "--edge") else { return nil }   // absent: default
        guard args.indices.contains(flag + 1),
              let edge = DockEdge(rawValue: args[flag + 1]) else {
            // Present but bad/missing: same default, but say so — a typo'd edge would
            // otherwise pin the strip to the wrong edge with a normal-looking startup log.
            FileHandle.standardError.write(
                Data("topdrawer-shell: --edge expects top|bottom|left|right — using the default\n".utf8))
            return nil
        }
        return edge
    }
}

let defaultEdge: DockEdge = .bottom
let edge = DockEdge.fromArguments(CommandLine.arguments) ?? defaultEdge
let stripMargin: Int32 = 8

let logger = Logger(label: "topdrawer-shell")
logger.info("topdrawer-shell starting (edge: \(edge.rawValue))")

gtk_init()

// MARK: - The strip window

let window = gtk_window_new()!
gtk_window_set_title(asWindow(window), "Top Drawer")
gtk_window_set_decorated(asWindow(window), 0)   // a dock strip, not an app window

// Layer shell: anchored to one edge of one monitor, on the top layer, reserving no
// exclusive space (windows slide under it).
guard gtk_layer_is_supported() != 0 else {
    logger.error("wlroots layer-shell not supported by this compositor — see the GNOME extension (LP-27)")
    exit(1)
}
gtk_layer_init_for_window(asWindow(window))
gtk_layer_set_layer(asWindow(window), GTK_LAYER_SHELL_LAYER_TOP)
gtk_layer_set_anchor(asWindow(window), GTK_LAYER_SHELL_EDGE_BOTTOM, edge == .bottom ? 1 : 0)
gtk_layer_set_anchor(asWindow(window), GTK_LAYER_SHELL_EDGE_TOP, edge == .top ? 1 : 0)
gtk_layer_set_anchor(asWindow(window), GTK_LAYER_SHELL_EDGE_LEFT, edge == .left ? 1 : 0)
gtk_layer_set_anchor(asWindow(window), GTK_LAYER_SHELL_EDGE_RIGHT, edge == .right ? 1 : 0)
gtk_layer_set_margin(asWindow(window), GTK_LAYER_SHELL_EDGE_BOTTOM, edge == .bottom ? stripMargin : 0)
gtk_layer_set_margin(asWindow(window), GTK_LAYER_SHELL_EDGE_TOP, edge == .top ? stripMargin : 0)
gtk_layer_set_margin(asWindow(window), GTK_LAYER_SHELL_EDGE_LEFT, edge == .left ? stripMargin : 0)
gtk_layer_set_margin(asWindow(window), GTK_LAYER_SHELL_EDGE_RIGHT, edge == .right ? stripMargin : 0)
gtk_layer_set_exclusive_zone(asWindow(window), 0)

// `--monitor <index>` pins the strip to one output; without it the compositor picks.
if let flag = CommandLine.arguments.firstIndex(of: "--monitor") {
    if CommandLine.arguments.indices.contains(flag + 1),
       let index = Int(CommandLine.arguments[flag + 1]),
       index >= 0,
       let display = gdk_display_get_default() {
        let monitors = gdk_display_get_monitors(display)
        let count = g_list_model_get_n_items(monitors)
        if UInt32(index) < count, let raw = g_list_model_get_item(monitors, UInt32(index)) {
            gtk_layer_set_monitor(asWindow(window), OpaquePointer(raw))
            g_object_unref(raw)
        } else {
            logger.warning("no monitor #\(index) (have \(count)) — leaving the choice to the compositor")
        }
    } else {
        // Same contract as --edge: present-but-bad falls back to the default, loudly —
        // a typo'd index (or a connector name like eDP-1) would otherwise land the
        // strip on the wrong output with a normal-looking startup log. `index >= 0`
        // stays in the guard: UInt32(negative) traps rather than failing.
        let got = CommandLine.arguments.indices.contains(flag + 1)
            ? CommandLine.arguments[flag + 1] : "nothing"
        logger.warning("--monitor expects a non-negative index, got '\(got)' — leaving the choice to the compositor")
    }
}

let strip = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12)!
gtk_widget_set_margin_start(strip, 10)
gtk_widget_set_margin_end(strip, 10)
gtk_widget_set_margin_top(strip, 6)
gtk_widget_set_margin_bottom(strip, 6)
gtk_window_set_child(asWindow(window), strip)

// Held as OpaquePointer: gtk_label_new returns a typed pointer but the label
// accessors take the opaque one — normalize once, at creation.
let stripLabel = OpaquePointer(gtk_label_new("Top Drawer — waiting for topdrawerd…")!)
gtk_box_append(asBox(strip), asWidget(stripLabel))

// MARK: - Pointer logging (the LP-20 interaction probe)

let motion = gtk_event_controller_motion_new()
gtk_widget_add_controller(window, motion)
gtkConnectEnter(motion) { x, y in
    logger.info("pointer entered the strip at (\(Int(x)), \(Int(y)))")
}
gtkConnect(motion, signal: "leave") {
    logger.info("pointer left the strip")
}

let click = gtk_gesture_click_new()
gtk_widget_add_controller(window, click)
gtkConnectClickReleased(click) { x, y in
    logger.info("strip clicked at (\(Int(x)), \(Int(y)))")
}

gtkConnectCloseRequest(window) {
    logger.info("strip closed")
    exit(0)
}

// MARK: - Content from the daemon

@Sendable
func renderTabs(_ tabs: [ShellTab]) {
    let text = tabs.map(\.title).joined(separator: "  ·  ")
    gtk_label_set_text(stripLabel, text.isEmpty ? "Top Drawer — no tabs" : text)
}

Task.detached(priority: .utility) {
    do {
        try await DBusClient.withSessionBus(auth: .external(userID: String(getuid()))) { connection in
            await DaemonClient.observeTabs(
                connection,
                onChange: { tabs in onMainLoop { renderTabs(tabs) } },
                onError: { error in
                    logger.warning("daemon unavailable: \(String(describing: error)) — retrying")
                })
        }
    } catch {
        // A session-bus failure ends the watch permanently; the strip keeps its last
        // content and the message says why (a dock shouldn't crash the session).
        logger.error("D-Bus session connection failed: \(String(describing: error))")
    }
}

// MARK: - Main loop (the GTK4 replacement for gtk_main)

gtk_widget_set_visible(window, 1)
let mainLoop = g_main_loop_new(nil, 0)!
g_main_loop_run(mainLoop)
#endif
