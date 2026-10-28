import SwiftUI

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

struct PosterView: View {
    let path: String?
    var small = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.quaternary)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                AsyncImage(url: TMDBImageURL.poster(path, small: small)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        if path != nil { ProgressView().controlSize(.small) }
                        else { placeholder }
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("影片海报")
    }

    private var placeholder: some View {
        Image(systemName: "film")
            .font(small ? .title3 : .largeTitle)
            .foregroundStyle(.secondary)
            .accessibilityLabel("暂无海报")
    }
}
