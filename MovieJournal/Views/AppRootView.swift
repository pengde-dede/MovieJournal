import SwiftData
import SwiftUI

struct AppRootView: View {
    let persistence: PersistenceController

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
        }
    }
}
