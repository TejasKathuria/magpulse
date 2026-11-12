import SwiftUI
import AppKit

@main
struct MagpulseApp: App {
    @StateObject private var manager = MagpulseManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 580, height: 700)

        MenuBarExtra {
            MenuBarView(manager: manager)
        } label: {
            Image(systemName: manager.isMasterEnabled && manager.isPulsing ? "bolt.horizontal.fill" : "bolt.horizontal")
        }
    }
}

