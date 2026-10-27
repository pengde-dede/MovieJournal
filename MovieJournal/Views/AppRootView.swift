import SwiftData
import SwiftUI

struct AppRootView: View {
    let persistence: PersistenceController
    @Environment(SettingsViewModel.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let container = persistence.container {
                LibraryView()
                    .modelContainer(container)
            } else if let errorDescription = persistence.errorDescription {
                StorageErrorView(errorDescription: errorDescription) {
                    persistence.reload()
                }
            } else {
                ProgressView("正在打开观影记录…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .task {
            persistence.loadIfNeeded()
            await settings.refreshIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await settings.refresh() }
            }
        }
    }
}
