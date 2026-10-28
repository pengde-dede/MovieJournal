import Foundation

nonisolated struct PersonSearchResult: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    /// TMDB 的主要职业，例如 Directing、Writing、Acting。
    let department: String?
    let profilePath: String?
    let knownFor: [String]

    var isDirector: Bool { department == "Directing" }

    var departmentTitle: String {
        switch department {
        case "Directing": "导演"
        case "Writing": "编剧"
        case "Acting": "演员"
        case "Production": "制片"
        case "Camera": "摄影"
        case "Editing": "剪辑"
        case "Sound": "音乐音效"
        default: "影视工作者"
        }
    }
}

nonisolated enum CreditRole: Equatable, Sendable {
    case director
    case creator

    var title: String {
        switch self {
        case .director: "执导"
        case .creator: "主创"
        }
    }
}

nonisolated struct CreditedWork: Identifiable, Equatable, Sendable {
    let result: MediaSearchResult
    let role: CreditRole

    var id: String { result.id }
}
