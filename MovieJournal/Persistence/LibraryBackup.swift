import Foundation
import SwiftData

nonisolated struct LibraryBackup: Codable {
    var version = 3
    var entries: [Entry]
    var posters: [String: Data]

    struct Visit: Codable {
        var date: Date?
        var rating: Int?
        var review: String
        var season: Int?
        // 版本 1/2 未保存观看编号。
        var id: UUID? = nil

        var hasContent: Bool { date != nil || rating != nil || !review.isEmpty || season != nil }

        func event(libraryEntryID: UUID) -> ViewingEvent {
            ViewingEvent(id: id ?? UUID(), libraryEntryID: libraryEntryID, date: date, rating: rating,
                         review: review, season: season)
        }

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
        var artworkFilenames: [String] {
            [filename, PosterCache.filename(for: details.seriesLookup?.series?.posterPath)].compactMap { $0 }
        }
        var libraryEntry: LibraryEntry {
            LibraryEntry(id: id, mediaKey: key, status: status ?? .watched, createdAt: created,
                         updatedAt: updated, latestViewingID: latest.id)
        }

        @MainActor
        func record() -> ViewingRecord {
            let d = details
            let entry = libraryEntry
            let record = ViewingRecord(id: entry.id, tmdbID: d.tmdbID, mediaType: d.mediaType, title: d.title,
                originalTitle: d.originalTitle, releaseYear: d.releaseYear, genres: d.genres,
                overview: d.overview, overviewLanguage: d.overviewLanguage, creatorNames: d.creatorNames,
                castNames: d.castNames, imdbID: d.imdbID, tmdbRating: d.tmdbRating, imdbRating: d.imdbRating,
                rottenTomatoesRating: d.rottenTomatoesRating, posterPath: d.posterPath, posterFilename: filename,
                seriesLookup: d.seriesLookup,
                watchStatus: entry.status, latestViewingID: entry.latestViewingID, watchedOn: latest.date,
                myRating: latest.rating, shortReview: latest.review, watchedSeason: latest.season,
                createdAt: entry.createdAt, metadataFetchedAt: d.fetchedAt)
            record.updatedAt = entry.updatedAt
            record.assignLatestViewingIDIfNeeded(hasHistory: !history.isEmpty)
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
            let entry = item.libraryEntry
            let earlier = try (history[entry.id] ?? []).map { row in
                guard let event = row.viewing else { throw Invalid.archive }
                return Visit(event: event)
            }
            return Entry(id: entry.id, details: MediaDetails(record: item), created: entry.createdAt, updated: entry.updatedAt,
                latest: item.latestViewing.map(Visit.init(event:)) ?? Visit(date: nil, rating: nil, review: "", season: nil),
                history: earlier, filename: item.posterFilename ?? PosterCache.filename(for: item.posterPath), status: entry.status)
        }
        var posters: [String: Data] = [:]
        for name in Set(entries.flatMap(\.artworkFilenames)) {
            do { posters[name] = try await cache.readData(filename: name) }
            catch PosterCacheError.localFileUnavailable { continue }
        }
        return Self(entries: entries, posters: posters)
    }

    @MainActor
    func additions(to context: ModelContext) throws -> [Entry] {
        guard (1...3).contains(version) else { throw Invalid.archive }
        let current = try RecordStore(context: context).recordsNewestFirst()
        var keys = Set(current.map(\.mediaKey))
        var ids = Set(current.map(\.id))
        var viewingIDs = Set(current.compactMap(\.latestViewingID))
        if version == 3 {
            viewingIDs.formUnion(try context.fetch(FetchDescriptor<EarlierViewing>()).compactMap(\.viewingID))
        }
        var pending: [Entry] = []
        for entry in entries {
            guard entry.details.tmdbID > 0, !entry.details.title.isEmpty,
                  entry.latest.isValid(for: entry.details.mediaType),
                  version == 1 || entry.status != nil,
                  version != 1 || (entry.latest.date != nil && entry.latest.rating != nil),
                  version == 3 || entry.latest.id == nil,
                  entry.history.allSatisfy({ $0.isValid(for: entry.details.mediaType)
                      && (version == 3 || ($0.id == nil && $0.isNoLater(than: entry.latest)))
                      && (version != 1 || ($0.date != nil && $0.rating != nil)) }),
                  entry.filename == nil || entry.filename == PosterCache.filename(for: entry.details.posterPath)
            else { throw Invalid.archive }
            if let lookup = entry.details.seriesLookup {
                guard entry.details.mediaType == .movie else { throw Invalid.archive }
                if let series = lookup.series, series.id <= 0 || Optional(series.name).nonEmpty == nil {
                    throw Invalid.archive
                }
            }
            guard keys.insert(entry.key).inserted else { continue }
            guard ids.insert(entry.id).inserted else { throw Invalid.archive }
            if version == 3 {
                let requiresLatest = entry.latest.hasContent || entry.status == .watched || !entry.history.isEmpty
                guard !requiresLatest || entry.latest.id != nil else { throw Invalid.archive }
                if let id = entry.latest.id, !viewingIDs.insert(id).inserted { throw Invalid.archive }
                for visit in entry.history {
                    guard let id = visit.id, viewingIDs.insert(id).inserted else { throw Invalid.archive }
                }
            }
            pending.append(entry)
        }
        return pending
    }

    @MainActor
    func restore(context: ModelContext, cache: any PosterFileManaging) async throws -> Int {
        let pending = try additions(to: context)
        for name in Set(pending.flatMap(\.artworkFilenames)) {
            if let data = posters[name] { try await cache.restorePoster(data, filename: name) }
        }
        // A second window may have added a work while files were being restored.
        let fresh = try additions(to: context)
        for entry in fresh {
            context.insert(entry.record())
            for visit in entry.history {
                context.insert(EarlierViewing(viewing: visit.event(libraryEntryID: entry.id)))
            }
        }
        do { try context.save() }
        catch { context.rollback(); throw error }
        return fresh.count
    }
}

private extension LibraryBackup.Visit {
    init(event: ViewingEvent) {
        self.init(date: event.date, rating: event.rating, review: event.review, season: event.season, id: event.id)
    }
}
