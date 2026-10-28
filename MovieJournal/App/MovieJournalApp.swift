import SwiftUI

@main
struct MovieJournalApp: App {
    @State private var persistence = PersistenceController()
    @State private var settings: SettingsViewModel
    private let catalog: any MediaCatalogServing
    private let posters: any PosterCaching

    init() {
        let keychain = KeychainService()
        let transport = HTTPClient()
        let tmdb = TMDBClient(transport: transport)
        let omdb = OMDbClient(transport: transport)
        posters = PosterCache(transport: transport)
        catalog = MediaCatalogService(keychain: keychain, tmdb: tmdb, omdb: omdb)
        _settings = State(initialValue: SettingsViewModel(keychain: keychain, validator: APIKeyValidator(tmdb: tmdb, omdb: omdb)))
    }

    var body: some Scene {
        WindowGroup("观影记录") {
            AppRootView(persistence: persistence, catalog: catalog, posters: posters)
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
