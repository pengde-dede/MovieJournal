import Foundation

nonisolated enum TMDBImageURL {
    static func poster(_ path: String?, small: Bool = false) -> URL? {
        image(path, size: small ? "w185" : "w500")
    }

    static func profile(_ path: String?) -> URL? {
        image(path, size: "h632")
    }

    private static func image(_ path: String?, size: String) -> URL? {
        guard let path, path.hasPrefix("/"), path.count > 1 else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "image.tmdb.org"
        components.path = "/t/p/\(size)\(path)"
        return components.url
    }
}
