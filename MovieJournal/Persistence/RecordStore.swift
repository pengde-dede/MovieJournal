import Foundation
import SwiftData

@MainActor
final class RecordStore {
    enum SaveError: LocalizedError, Equatable {
        case duplicate(existingRecordID: UUID)
        case invalidRating
        case invalidViewing
        case invalidSeason
        case recordNotFound
        case imdbIDChanged

        var errorDescription: String? {
            switch self {
            case .duplicate:
                "这部作品已经在观影记录中，可以打开已有记录。"
            case .invalidRating:
                "我的评分需要是 1–10 的整数。"
            case .invalidViewing:
                "请先将作品标为已看，再记录重看。"
            case .invalidSeason:
                "请填写有效的剧集季数，例如 2（只填写大于 0 的整数）。"
            case .recordNotFound:
                "这条记录已被其他窗口删除，请返回资料库查看。"
            case .imdbIDChanged:
                "作品的 IMDb 编号已改变，请重新打开记录后再刷新。"
            }
        }
    }

    private let context: ModelContext
    private let saveChanges: () throws -> Void

    // 测试可注入保存失败，核对回滚；正式使用仍显式保存同一个上下文。
    init(context: ModelContext, saveChanges: (() throws -> Void)? = nil) {
        self.context = context
        self.saveChanges = saveChanges ?? { try context.save() }
    }

    func recordsNewestFirst() throws -> [ViewingRecord] {
        let descriptor = FetchDescriptor<ViewingRecord>(
            sortBy: [SortDescriptor(\ViewingRecord.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func existingRecord(tmdbID: Int, mediaType: MediaType) throws -> ViewingRecord? {
        let key = mediaType.mediaKey(tmdbID: tmdbID)
        var descriptor = FetchDescriptor<ViewingRecord>(
            predicate: #Predicate { $0.mediaKey == key }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func setPosterFilename(_ filename: String, recordID: UUID, expectedPath: String?) throws {
        var descriptor = FetchDescriptor<ViewingRecord>(predicate: #Predicate { $0.id == recordID })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first, record.posterPath == expectedPath,
              record.posterFilename != filename else { return }
        let previous = record.posterFilename
        record.posterFilename = filename
        do { try saveChanges() }
        catch {
            record.posterFilename = previous
            throw error
        }
    }

    func updatePersonalInformation(recordID: UUID, watchedOn: Date?, myRating: Int?,
                                   shortReview: String, watchedSeason: Int?, watchStatus: WatchStatus? = nil) throws {
        let record = try requiredRecord(id: recordID)
        if let myRating, !(1...10).contains(myRating) { throw SaveError.invalidRating }
        if record.mediaType == .tv, let watchedSeason, watchedSeason < 1 {
            throw SaveError.invalidSeason
        }
        // 只更新个人信息，不用旧草稿覆盖平台资料或其他窗口补存的海报引用。
        if let watchStatus { record.watchStatus = watchStatus }
        record.watchedOn = watchedOn
        record.myRating = myRating
        record.shortReview = shortReview.trimmingCharacters(in: .whitespacesAndNewlines)
        record.watchedSeason = record.mediaType == .tv ? watchedSeason : nil
        record.assignLatestViewingIDIfNeeded()
        record.updatedAt = .now
        do { try promoteLatestViewing(record); try saveChanges() }
        catch {
            context.rollback()
            throw error
        }
    }

    func setWatchStatus(_ status: WatchStatus, recordID: UUID) throws {
        let record = try requiredRecord(id: recordID)
        guard record.watchStatus != status else { return }
        record.watchStatus = status
        if status == .watched, record.watchedOn == nil { record.watchedOn = .now }
        record.assignLatestViewingIDIfNeeded()
        record.updatedAt = .now
        do { try saveChanges() } catch { context.rollback(); throw error }
    }

    func updateSupplementalRatings(_ ratings: PlatformRatings, recordID: UUID, expectedIMDbID: String) throws {
        let record = try requiredRecord(id: recordID)
        guard record.imdbID.nonEmpty == expectedIMDbID else { throw SaveError.imdbIDChanged }
        // 接口没有返回的项目保留原值，不能用缺失评分覆盖已有评分。
        let imdb = ratings.imdb ?? record.imdbRating
        let tomatoes = ratings.rottenTomatoes ?? record.rottenTomatoesRating
        guard imdb != record.imdbRating || tomatoes != record.rottenTomatoesRating else { return }
        record.imdbRating = imdb
        record.rottenTomatoesRating = tomatoes
        do { try saveChanges() }
        catch {
            context.rollback()
            throw error
        }
    }

    func addViewing(recordID: UUID, draft: RecordDraft) throws {
        let record = try requiredRecord(id: recordID)
        if let message = draft.validationMessage { throw RecordDraft.DraftError.invalid(message) }
        guard record.watchStatus == .watched, draft.watchStatus == .watched else { throw SaveError.invalidViewing }
        let viewing = ViewingEvent(libraryEntryID: recordID, date: draft.watchedOn, rating: draft.myRating,
                                   review: draft.shortReview.trimmingCharacters(in: .whitespacesAndNewlines),
                                   season: record.mediaType == .tv ? draft.watchedSeason : nil)
        if let newDate = viewing.date, let currentDate = record.watchedOn, newDate < currentDate {
            context.insert(EarlierViewing(viewing: viewing))
        } else {
            if let current = record.latestViewing { context.insert(EarlierViewing(viewing: current)) }
            record.setLatestViewing(viewing)
        }
        record.updatedAt = .now
        do { try promoteLatestViewing(record); try saveChanges() } catch { context.rollback(); throw error }
    }

    // Unknown dates stay unknown; when both visits have dates, keep the latest on the work.
    private func promoteLatestViewing(_ record: ViewingRecord) throws {
        guard let current = record.latestViewing, let date = current.date else { return }
        let identifier = record.id
        var descriptor = FetchDescriptor<EarlierViewing>(
            predicate: #Predicate { $0.recordID == identifier },
            sortBy: [SortDescriptor(\.watchedOn, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let previous = try context.fetch(descriptor).first,
              let promoted = previous.viewing, let previousDate = promoted.date, previousDate > date else { return }
        previous.replaceViewing(current)
        record.setLatestViewing(promoted)
    }

    func delete(recordID: UUID) throws {
        let record = try requiredRecord(id: recordID)
        let history = try context.fetch(FetchDescriptor<EarlierViewing>(predicate: #Predicate { $0.recordID == recordID }))
        for viewing in history { context.delete(viewing) }
        context.delete(record)
        do { try saveChanges() }
        catch {
            context.rollback()
            throw error
        }
    }

    private func requiredRecord(id: UUID) throws -> ViewingRecord {
        var descriptor = FetchDescriptor<ViewingRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { throw SaveError.recordNotFound }
        return record
    }

    func insert(_ record: ViewingRecord) throws {
        // 不依赖 unique 冲突报错：SwiftData 的唯一约束可能执行覆盖更新。
        if let existing = try existingRecord(tmdbID: record.tmdbID, mediaType: record.mediaType) {
            throw SaveError.duplicate(existingRecordID: existing.id)
        }
        if let rating = record.myRating, !(1...10).contains(rating) {
            throw SaveError.invalidRating
        }

        if record.mediaType == .tv, let season = record.watchedSeason, season < 1 {
            throw SaveError.invalidSeason
        }
        record.assignLatestViewingIDIfNeeded()
        context.insert(record)
        do {
            try saveChanges()
        } catch {
            context.rollback()
            throw error
        }
    }
}
