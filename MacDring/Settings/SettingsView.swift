import SwiftUI
import UpdraftKit

/// The tabbed settings window: General, Appearance, Tabs, About.
struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: TabStore
    let registry: DisplayRegistry
    @ObservedObject var router: SettingsRouter
    @ObservedObject var updateChecker: UpdateChecker
    /// Asks the app to briefly outline a tab’s pill (the Tabs pane’s “Locate Tab”).
    let onLocateTab: (UUID) -> Void

    var body: some View {
        TabView(selection: $router.section) {
            GeneralView(preferences: preferences, updateChecker: updateChecker)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsSection.general)

            AppearanceView(preferences: preferences)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(SettingsSection.appearance)

            TabsView(preferences: preferences, store: store, registry: registry, router: router,
                     onLocateTab: onLocateTab)
                .tabItem { Label("Tabs", systemImage: "square.grid.2x2") }
                .tag(SettingsSection.tabs)

            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsSection.about)
        }
        // Fill the window (and set a sensible minimum) so resizing the window
        // resizes the content, instead of pinning it to a fixed size.
        .frame(minWidth: 560, minHeight: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
