import Foundation

struct RecordDraft {
    // 只标识本次编辑，用于隔离旧表单的迟到事件，不写入数据库。
    let editingID = UUID()
    var details: MediaDetails
    var posterFilename: String?
    var watchedOn: Date = .now
    var myRating: Int?
    var shortReview = ""
    // 保留正在输入的原文，校验失败也不丢失；只有有效整数才进入持久化模型。
    var watchedSeasonText = ""
    var watchedSeason: Int? {
        get {
            let text = watchedSeasonText.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: .widthInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            guard let value = Int(text), value > 0 else { return nil }
            return value
        }
        set { watchedSeasonText = newValue.map(String.init) ?? "" }
    }

    var seasonValidationMessage: String? {
        guard details.mediaType == .tv, watchedSeason == nil else { return nil }
        if watchedSeasonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写看到第几季，例如 2（只填写数字）。"
        }
        return "请只填写大于 0 的整数，例如 2（表示第 2 季）。"
    }

    var validationMessage: String? {
        guard let myRating, (1...10).contains(myRating) else {
            return "请选择 1–10 分的个人评分。"
        }
        return seasonValidationMessage
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
            posterFilename: posterFilename,
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
