import SwiftUI

@main
struct MovieJournalApp: App {
    @State private var persistence = PersistenceController()
    @State private var settings: SettingsViewModel
    @State private var posterCleanup: PosterCleanupCoordinator
    private let catalog: any MediaCatalogServing
    private let posters: any PosterFileManaging
    private let thumbnails: any PosterThumbnailLoading

    init() {
        let keychain = KeychainService()
        let transport = HTTPClient()
        let tmdb = TMDBClient(transport: transport)
        let omdb = OMDbClient(transport: transport)
        let posterCache = PosterCache(transport: transport)
        posters = posterCache
        _posterCleanup = State(initialValue: PosterCleanupCoordinator(cache: posterCache))
        thumbnails = PosterThumbnailCache(transport: transport)
        catalog = MediaCatalogService(keychain: keychain, tmdb: tmdb, omdb: omdb)
        _settings = State(initialValue: SettingsViewModel(keychain: keychain, validator: APIKeyValidator(tmdb: tmdb, omdb: omdb)))
    }

    var body: some Scene {
        WindowGroup("观影记录") {
            AppRootView(persistence: persistence, catalog: catalog, posters: posters, cleanup: posterCleanup)
                .environment(\.posterThumbnails, thumbnails)
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
