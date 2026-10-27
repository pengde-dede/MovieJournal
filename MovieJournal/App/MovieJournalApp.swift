import SwiftUI

@main
struct MovieJournalApp: App {
    @State private var persistence = PersistenceController()

    var body: some Scene {
        WindowGroup("观影记录") {
            AppRootView(persistence: persistence)
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
        .defaultSize(width: 920, height: 680)

        Settings {
            SettingsView()
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
    }
}
