import Foundation
import SwiftData

@MainActor
final class RecordStore {
    enum SaveError: LocalizedError, Equatable {
        case duplicate(existingRecordID: UUID)
        case invalidRating
        case invalidSeason
        case recordNotFound

        var errorDescription: String? {
            switch self {
            case .duplicate:
                "这部作品已经在观影记录中，可以打开已有记录。"
            case .invalidRating:
                "我的评分需要是 1–10 的整数。"
            case .invalidSeason:
                "请填写有效的剧集季数，例如 2（只填写大于 0 的整数）。"
            case .recordNotFound:
                "这条记录已被其他窗口删除，请返回资料库查看。"
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

    func updatePersonalInformation(recordID: UUID, watchedOn: Date, myRating: Int,
                                   shortReview: String, watchedSeason: Int?) throws {
        let record = try requiredRecord(id: recordID)
        guard (1...10).contains(myRating) else { throw SaveError.invalidRating }
        if record.mediaType == .tv, (watchedSeason ?? 0) < 1 {
            throw SaveError.invalidSeason
        }
        // 只更新个人信息，不用旧草稿覆盖平台资料或其他窗口补存的海报引用。
        record.watchedOn = watchedOn
        record.myRating = myRating
        record.shortReview = shortReview.trimmingCharacters(in: .whitespacesAndNewlines)
        record.watchedSeason = record.mediaType == .tv ? watchedSeason : nil
        record.updatedAt = .now
        do { try saveChanges() }
        catch {
            context.rollback()
            throw error
        }
    }

    func delete(recordID: UUID) throws {
        let record = try requiredRecord(id: recordID)
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
        guard (1...10).contains(record.myRating) else {
            throw SaveError.invalidRating
        }

        context.insert(record)
        do {
            try saveChanges()
        } catch {
            context.rollback()
            throw error
        }
    }
}
