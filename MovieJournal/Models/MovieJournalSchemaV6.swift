import Foundation
import SwiftData

// 保存电影导演的稳定人物标识、名称和头像路径。
nonisolated enum MovieJournalSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }
    static var models: [any PersistentModel.Type] { [ViewingRecord.self, MovieJournalSchemaV4.EarlierViewing.self] }

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

        var seriesChecked: Bool?
        var seriesID: Int?
        var seriesName: String?
        var seriesPosterPath: String?
        // nil 为待补全，编码后的空数组为查过但没有可用的导演资料。
        private var directorCreditsData: Data?

        var movieDirectors: [MovieDirector]? {
            guard let directorCreditsData else { return nil }
            return try? JSONDecoder().decode([MovieDirector].self, from: directorCreditsData)
        }

        func setMovieDirectors(_ directors: [MovieDirector]) throws {
            directorCreditsData = try JSONEncoder().encode(directors)
        }

        func needsLookup(_ kind: MovieMetadataKind) -> Bool {
            guard mediaType == .movie else { return false }
            switch kind {
            case .series: return needsSeriesLookup
            case .directors: return directorCreditsData == nil
            }
        }

        var groupArtworkFilenames: [String] {
            [PosterCache.filename(for: seriesPosterPath)].compactMap { $0 }
                + (movieDirectors ?? []).compactMap(\.profileFilename)
        }

        var needsSeriesLookup: Bool { mediaType == .movie && seriesChecked != true }

        var movieSeries: MovieSeries? {
            guard let seriesID, let seriesName else { return nil }
            return MovieSeries(id: seriesID, name: seriesName, posterPath: seriesPosterPath)
        }

        var seriesLookup: MovieSeriesLookup? {
            get {
                guard seriesChecked == true else { return nil }
                return MovieSeriesLookup(series: movieSeries)
            }
            set {
                seriesChecked = newValue.map { _ in true }
                seriesID = newValue?.series?.id
                seriesName = newValue?.series?.name
                seriesPosterPath = newValue?.series?.posterPath
            }
        }

        var watchStatusRawValue: String = "watched"
        var latestViewingID: UUID?
        var watchedOn: Date?
        var myRating: Int?
        var shortReview: String
        var watchedSeason: Int?
        private(set) var createdAt: Date
        var updatedAt: Date
        var metadataFetchedAt: Date

        var watchStatus: WatchStatus {
            get { WatchStatus(rawValue: watchStatusRawValue) ?? .watched }
            set { watchStatusRawValue = newValue.rawValue }
        }

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
            seriesLookup: MovieSeriesLookup? = nil,
            movieDirectors: [MovieDirector]? = nil,
            watchStatus: WatchStatus = .watched,
            latestViewingID: UUID? = nil,
            watchedOn: Date? = .now,
            myRating: Int? = nil,
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
            self.watchStatusRawValue = watchStatus.rawValue
            self.latestViewingID = latestViewingID
            self.watchedOn = watchedOn
            self.myRating = myRating
            self.shortReview = shortReview
            self.watchedSeason = mediaType == .tv ? watchedSeason : nil
            self.createdAt = createdAt
            self.updatedAt = createdAt
            self.metadataFetchedAt = metadataFetchedAt
            if mediaType == .movie {
                self.seriesLookup = seriesLookup
                if let movieDirectors { try? setMovieDirectors(movieDirectors) }
            }
            assignLatestViewingIDIfNeeded()
        }
    }
}

typealias EarlierViewing = MovieJournalSchemaV4.EarlierViewing
typealias ViewingRecord = MovieJournalSchemaV6.ViewingRecord
