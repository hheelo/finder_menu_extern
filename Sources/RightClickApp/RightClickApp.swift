import SwiftUI

@main
struct RightClickApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 640, minHeight: 440)
                .onOpenURL { model.handle(url: $0) }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        model.refreshExtensionStatus()
                        Task { await model.refreshDiagnostics() }
                    }
                }
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 560, height: 520)
        }
    }
}
