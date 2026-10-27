import Foundation
import SwiftData

// 发布后保留此版本；未来新增字段时添加 V2 和相应迁移步骤。
nonisolated enum MovieJournalSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [ViewingRecord.self] }

    @Model
    final class ViewingRecord {
        @Attribute(.unique) private(set) var id: UUID
        @Attribute(.unique) private(set) var mediaKey: String
        private(set) var tmdbID: Int
        private(set) var mediaTypeRawValue: String

        var title: String
        var originalTitle: String
        var releaseYear: Int?
        var genres: [String]
        var overview: String
        // 中文简介缺失时保存英文内容，并据此显示“英文简介”。
        var overviewLanguage: String
        var creatorNames: [String]
        var castNames: [String]

        var imdbID: String?
        var tmdbRating: Double?
        var imdbRating: Double?
        var rottenTomatoesRating: Int?
        var posterPath: String?
        // 仅保存相对文件名，不把机器相关的绝对路径写进数据库。
        var posterFilename: String?

        var watchedOn: Date
        var myRating: Int
        var shortReview: String
        var watchedSeason: Int?
        private(set) var createdAt: Date
        var updatedAt: Date
        var metadataFetchedAt: Date

        var mediaType: MediaType {
            // 所有新记录都通过下方的强类型初始化方法创建。
            MediaType(rawValue: mediaTypeRawValue) ?? .movie
        }

        init(
            id: UUID = UUID(),
            tmdbID: Int,
            mediaType: MediaType,
            title: String,
            originalTitle: String = "",
            releaseYear: Int? = nil,
            genres: [String] = [],
            overview: String = "",
            overviewLanguage: String = "zh-CN",
            creatorNames: [String] = [],
            castNames: [String] = [],
            imdbID: String? = nil,
            tmdbRating: Double? = nil,
            imdbRating: Double? = nil,
            rottenTomatoesRating: Int? = nil,
            posterPath: String? = nil,
            posterFilename: String? = nil,
            watchedOn: Date = .now,
            myRating: Int,
            shortReview: String = "",
            watchedSeason: Int? = nil,
            createdAt: Date = .now,
            metadataFetchedAt: Date = .now
        ) {
            self.id = id
            self.mediaKey = mediaType.mediaKey(tmdbID: tmdbID)
            self.tmdbID = tmdbID
            self.mediaTypeRawValue = mediaType.rawValue
            self.title = title
            self.originalTitle = originalTitle
            self.releaseYear = releaseYear
            self.genres = genres
            self.overview = overview
            self.overviewLanguage = overviewLanguage
            self.creatorNames = creatorNames
            self.castNames = Array(castNames.prefix(5))
            self.imdbID = imdbID
            self.tmdbRating = tmdbRating
            self.imdbRating = imdbRating
            self.rottenTomatoesRating = rottenTomatoesRating
            self.posterPath = posterPath
            self.posterFilename = posterFilename
            self.watchedOn = watchedOn
            self.myRating = myRating
            self.shortReview = shortReview
            self.watchedSeason = mediaType == .tv ? watchedSeason : nil
            self.createdAt = createdAt
            self.updatedAt = createdAt
            self.metadataFetchedAt = metadataFetchedAt
        }
    }
}

typealias ViewingRecord = MovieJournalSchemaV1.ViewingRecord
