import SwiftUI

@main
struct MovieJournalApp: App {
    @State private var persistence = PersistenceController()
    @State private var settings: SettingsViewModel
    @State private var trialSettings: TrialSettingsViewModel
    @State private var posterCleanup: PosterCleanupCoordinator
    @State private var metadataBackfill = MovieMetadataBackfill()
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
        let trialAccess = TrialCatalogAccess(keychain: keychain)
        catalog = MediaCatalogService(keychain: keychain, tmdb: tmdb, omdb: omdb, trial: trialAccess)
        _trialSettings = State(initialValue: TrialSettingsViewModel(access: trialAccess))
        _settings = State(initialValue: SettingsViewModel(keychain: keychain, validator: APIKeyValidator(tmdb: tmdb, omdb: omdb)))
    }

    var body: some Scene {
        WindowGroup("观影记录") {
            AppRootView(persistence: persistence, catalog: catalog, posters: posters, cleanup: posterCleanup,
                        metadataBackfill: metadataBackfill)
                .environment(\.posterThumbnails, thumbnails)
                .environment(settings)
                .environment(trialSettings)
                .task { await trialSettings.refresh() }
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
        .defaultSize(width: 920, height: 680)

        Settings {
            SettingsView()
                .environment(settings)
                .environment(trialSettings)
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
    }
}
