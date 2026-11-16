import Foundation

// 作品资料由 MediaDetails 表示。个人收藏与观看事件使用各自的标识。
nonisolated struct LibraryEntry: Codable, Equatable, Sendable {
    let id: UUID
    let mediaKey: String
    let status: WatchStatus
    let createdAt: Date
    let updatedAt: Date
    let latestViewingID: UUID?
}

nonisolated struct ViewingEvent: Codable, Equatable, Sendable {
    var id = UUID()
    let libraryEntryID: UUID
    let date: Date?
    let rating: Int?
    let review: String
    let season: Int?
}

extension ViewingRecord {
    var libraryEntry: LibraryEntry {
        LibraryEntry(id: id, mediaKey: mediaKey, status: watchStatus, createdAt: createdAt,
                     updatedAt: updatedAt, latestViewingID: latestViewingID)
    }

    var latestViewing: ViewingEvent? {
        guard let latestViewingID else { return nil }
        return ViewingEvent(id: latestViewingID, libraryEntryID: id, date: watchedOn,
                            rating: myRating, review: shortReview, season: watchedSeason)
    }

    func assignLatestViewingIDIfNeeded(hasHistory: Bool = false) {
        guard latestViewingID == nil else { return }
        if hasHistory || watchStatus == .watched || watchedOn != nil || myRating != nil
            || !shortReview.isEmpty || watchedSeason != nil {
            latestViewingID = UUID()
        }
    }

    func setLatestViewing(_ viewing: ViewingEvent) {
        latestViewingID = viewing.id
        watchedOn = viewing.date
        myRating = viewing.rating
        shortReview = viewing.review
        watchedSeason = viewing.season
    }
}

extension EarlierViewing {
    var viewing: ViewingEvent? {
        guard let viewingID else { return nil }
        return ViewingEvent(id: viewingID, libraryEntryID: recordID, date: watchedOn,
                            rating: rating, review: review, season: season)
    }

    func replaceViewing(_ viewing: ViewingEvent) {
        viewingID = viewing.id
        watchedOn = viewing.date
        rating = viewing.rating
        review = viewing.review
        season = viewing.season
    }
}

extension MovieJournalSchemaV4.ViewingRecord {
    func assignLatestViewingIDIfNeeded(hasHistory: Bool = false) {
        guard latestViewingID == nil else { return }
        if hasHistory || watchStatus == .watched || watchedOn != nil || myRating != nil
            || !shortReview.isEmpty || watchedSeason != nil {
            latestViewingID = UUID()
        }
    }
}
