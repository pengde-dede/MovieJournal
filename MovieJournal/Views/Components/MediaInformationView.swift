import SwiftUI

struct MediaInformationView: View {
    let details: MediaDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 22) {
                PosterView(path: details.posterPath)
                    .frame(width: 170)
                VStack(alignment: .leading, spacing: 12) {
                    Text(details.title).font(.title.bold())
                    if details.originalTitle != details.title {
                        Text(details.originalTitle).font(.title3).foregroundStyle(.secondary)
                    }
                    Text("\(details.mediaType.title) · \(details.releaseYear.map(String.init) ?? "年份未知")")
                        .foregroundStyle(.secondary)
                    Text(details.genres.isEmpty ? "暂无类型信息" : details.genres.joined(separator: " · "))
                    credit(details.mediaType == .movie ? "导演" : "主创", names: details.creatorNames)
                    credit("主演", names: details.castNames)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                rating("TMDB", value: decimalRating(details.tmdbRating))
                rating("IMDb", value: decimalRating(details.imdbRating))
                rating("烂番茄", value: details.rottenTomatoesRating.map { "\($0)%" } ?? "暂无评分")
            }
            GroupBox(details.overviewLanguage == "en" ? "英文简介" : "简介") {
                Text(details.overview.isEmpty ? "暂无简介" : details.overview)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            if let note = details.informationNote {
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
        }
        .textSelection(.enabled)
    }

    private func credit(_ label: String, names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(names.isEmpty ? "暂无信息" : names.joined(separator: " / "))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func rating(_ title: String, value: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private func decimalRating(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) + "/10" } ?? "暂无评分"
    }
}
