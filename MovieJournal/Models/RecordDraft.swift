import Foundation

struct RecordDraft {
    var details: MediaDetails
    var watchedOn: Date = .now
    var myRating: Int?
    var shortReview = ""
    var watchedSeason: Int?

    var validationMessage: String? {
        guard let myRating, (1...10).contains(myRating) else {
            return "请选择 1–10 分的个人评分。"
        }
        if details.mediaType == .tv, (watchedSeason ?? 0) < 1 {
            return "请填写看到第几季，季数需要是大于 0 的整数。"
        }
        return nil
    }

    func makeRecord() throws -> ViewingRecord {
        if let message = validationMessage { throw DraftError.invalid(message) }
        guard let myRating else { throw DraftError.invalid("请选择个人评分。") }
        return ViewingRecord(
            tmdbID: details.tmdbID,
            mediaType: details.mediaType,
            title: details.title,
            originalTitle: details.originalTitle,
            releaseYear: details.releaseYear,
            genres: details.genres,
            overview: details.overview,
            overviewLanguage: details.overviewLanguage,
            creatorNames: details.creatorNames,
            castNames: details.castNames,
            imdbID: details.imdbID,
            tmdbRating: details.tmdbRating,
            imdbRating: details.imdbRating,
            rottenTomatoesRating: details.rottenTomatoesRating,
            posterPath: details.posterPath,
            watchedOn: watchedOn,
            myRating: myRating,
            shortReview: shortReview.trimmingCharacters(in: .whitespacesAndNewlines),
            watchedSeason: details.mediaType == .tv ? watchedSeason : nil,
            metadataFetchedAt: details.fetchedAt
        )
    }

    enum DraftError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self { case .invalid(let message): message }
        }
    }
}
