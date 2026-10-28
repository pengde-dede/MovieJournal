import Foundation

nonisolated enum TMDBImageURL {
    static func poster(_ path: String?, small: Bool = false) -> URL? {
        guard let path, path.hasPrefix("/"), path.count > 1 else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "image.tmdb.org"
        components.path = "/t/p/\(small ? "w185" : "w500")\(path)"
        return components.url
    }
}
