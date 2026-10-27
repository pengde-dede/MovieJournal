import SwiftUI

@main
struct MovieJournalApp: App {
    @State private var persistence = PersistenceController()
    @State private var settings = SettingsViewModel(keychain: KeychainService())

    var body: some Scene {
        WindowGroup("观影记录") {
            AppRootView(persistence: persistence)
                .environment(settings)
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
        .defaultSize(width: 920, height: 680)

        Settings {
            SettingsView()
                .environment(settings)
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
    }
}
