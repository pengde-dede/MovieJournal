import Foundation

nonisolated enum WatchStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case wantToWatch
    case watching
    case watched

    var id: String { rawValue }
    var title: String {
        switch self {
        case .wantToWatch: "想看"
        case .watching: "在看"
        case .watched: "已看"
        }
    }
    var systemImage: String {
        switch self {
        case .wantToWatch: "bookmark"
        case .watching: "play.circle"
        case .watched: "checkmark.circle"
        }
    }
}

nonisolated enum LibraryStatusFilter: String, CaseIterable, Identifiable {
    case all, wantToWatch, watching, watched
    var id: Self { self }
    var status: WatchStatus? { WatchStatus(rawValue: rawValue) }
    var title: String { status?.title ?? "全部状态" }
    func includes(_ status: WatchStatus) -> Bool { self == .all || self.status == status }
}
