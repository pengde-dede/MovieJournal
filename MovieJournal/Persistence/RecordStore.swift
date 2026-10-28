import Foundation
import SwiftData

@MainActor
final class RecordStore {
    enum SaveError: LocalizedError, Equatable {
        case duplicate(existingRecordID: UUID)
        case invalidRating

        var errorDescription: String? {
            switch self {
            case .duplicate:
                "这部作品已经在观影记录中，可以打开已有记录。"
            case .invalidRating:
                "我的评分需要是 1–10 的整数。"
            }
        }
    }

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
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
        do { try context.save() }
        catch {
            record.posterFilename = previous
            throw error
        }
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
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
