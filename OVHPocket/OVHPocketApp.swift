import SwiftUI

@main
struct OVHPocketApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("nativeAppearance") private var appearance = "system"
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).tint(Theme.primary)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .task { await store.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, store.connection != nil, !store.connecting, store.consoleDestination == nil {
                        Task { await store.refresh(); if store.connection != nil { store.nativeRevision += 1 } }
                    }
                }
        }
    }
}
