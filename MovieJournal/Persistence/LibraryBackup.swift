import Foundation
import SwiftData

nonisolated struct LibraryBackup: Codable {
    var version = 2
    var entries: [Entry]
    var posters: [String: Data]

    struct Visit: Codable {
        var date: Date?
        var rating: Int?
        var review: String
        var season: Int?

        func isValid(for type: MediaType) -> Bool {
            (rating.map { (1...10).contains($0) } ?? true) && (type == .movie ? season == nil : (season.map { $0 > 0 } ?? true))
        }

        func isNoLater(than latest: Visit) -> Bool {
            guard let date, let latestDate = latest.date else { return true }
            return date <= latestDate
        }
    }

    struct Entry: Codable {
        var id: UUID
        var details: MediaDetails
        var created: Date
        var updated: Date
        var latest: Visit
        var history: [Visit]
        var filename: String?
        // Missing only in version 1 backups, whose entries were all watched.
        var status: WatchStatus? = nil

        var key: String { details.mediaType.mediaKey(tmdbID: details.tmdbID) }

        @MainActor
        func record() -> ViewingRecord {
            let d = details
            let record = ViewingRecord(id: id, tmdbID: d.tmdbID, mediaType: d.mediaType, title: d.title,
                originalTitle: d.originalTitle, releaseYear: d.releaseYear, genres: d.genres,
                overview: d.overview, overviewLanguage: d.overviewLanguage, creatorNames: d.creatorNames,
                castNames: d.castNames, imdbID: d.imdbID, tmdbRating: d.tmdbRating, imdbRating: d.imdbRating,
                rottenTomatoesRating: d.rottenTomatoesRating, posterPath: d.posterPath, posterFilename: filename,
                watchStatus: status ?? .watched, watchedOn: latest.date, myRating: latest.rating, shortReview: latest.review,
                watchedSeason: latest.season, createdAt: created, metadataFetchedAt: d.fetchedAt)
            record.updatedAt = updated
            return record
        }
    }

    enum Invalid: LocalizedError {
        case archive
        var errorDescription: String? { "备份版本不受支持，或内容不完整、存在冲突。" }
    }

    @MainActor
    static func snapshot(context: ModelContext, cache: any PosterFileManaging) async throws -> Self {
        let history = Dictionary(grouping: try context.fetch(FetchDescriptor<EarlierViewing>()), by: \.recordID)
        let entries = try RecordStore(context: context).recordsNewestFirst().map { item in
            let earlier = (history[item.id] ?? []).map { Visit(date: $0.watchedOn, rating: $0.rating, review: $0.review, season: $0.season) }
            return Entry(id: item.id, details: MediaDetails(record: item), created: item.createdAt, updated: item.updatedAt,
                latest: Visit(date: item.watchedOn, rating: item.myRating, review: item.shortReview, season: item.watchedSeason),
                history: earlier, filename: item.posterFilename ?? PosterCache.filename(for: item.posterPath), status: item.watchStatus)
        }
        var posters: [String: Data] = [:]
        for name in Set(entries.compactMap(\.filename)) {
            do { posters[name] = try await cache.readData(filename: name) }
            catch PosterCacheError.localFileUnavailable { continue }
        }
        return Self(entries: entries, posters: posters)
    }

    @MainActor
    func additions(to context: ModelContext) throws -> [Entry] {
        guard version == 1 || version == 2 else { throw Invalid.archive }
        let current = try RecordStore(context: context).recordsNewestFirst()
        var keys = Set(current.map(\.mediaKey))
        var ids = Set(current.map(\.id))
        var pending: [Entry] = []
        for entry in entries {
            guard entry.details.tmdbID > 0, !entry.details.title.isEmpty,
                  entry.latest.isValid(for: entry.details.mediaType),
                  version == 1 || entry.status != nil,
                  version != 1 || (entry.latest.date != nil && entry.latest.rating != nil),
                  entry.history.allSatisfy({ $0.isValid(for: entry.details.mediaType) && $0.isNoLater(than: entry.latest)
                      && (version != 1 || ($0.date != nil && $0.rating != nil)) }),
                  entry.filename == nil || entry.filename == PosterCache.filename(for: entry.details.posterPath)
            else { throw Invalid.archive }
            guard keys.insert(entry.key).inserted else { continue }
            guard ids.insert(entry.id).inserted else { throw Invalid.archive }
            pending.append(entry)
        }
        return pending
    }

    @MainActor
    func restore(context: ModelContext, cache: any PosterFileManaging) async throws -> Int {
        let pending = try additions(to: context)
        for name in Set(pending.compactMap(\.filename)) {
            if let data = posters[name] { try await cache.restorePoster(data, filename: name) }
        }
        // A second window may have added a work while files were being restored.
        let fresh = try additions(to: context)
        for entry in fresh {
            context.insert(entry.record())
            for visit in entry.history {
                context.insert(EarlierViewing(recordID: entry.id, watchedOn: visit.date, rating: visit.rating,
                                              review: visit.review, season: visit.season))
            }
        }
        do { try context.save() }
        catch { context.rollback(); throw error }
        return fresh.count
    }
}
