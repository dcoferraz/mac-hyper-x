import SwiftUI

@main
struct QuadCastControlApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("QuadCast Control", id: "controls") {
            ControlsView()
                .environmentObject(state)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(state)
        } label: {
            Image(systemName: menuBarSymbol)
        }
        // A panel rather than a plain menu, so the gain and volume sliders work.
        .menuBarExtraStyle(.window)
    }

    /// Muted beats disconnected: it's the thing you most need to see at a glance.
    private var menuBarSymbol: String {
        if state.muted == true { return "mic.slash.fill" }
        return state.connected ? "mic.fill" : "mic.slash"
    }
}
