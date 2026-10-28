import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import MovieJournal

@Suite("季数输入与校验")
@MainActor
struct SeasonInputTests {
    @Test("带文字的季数保留原输入，编辑短评或更新评分时也不丢失", arguments: ["第2季", "二"])
    func invalidTextRemainsVisible(value: String) throws {
        var draft: RecordDraft? = RecordDraft(details: Fixtures.details(Fixtures.series))
        draft?.myRating = 8
        draft?.watchedSeason = 3
        let source = Binding<RecordDraft?>(get: { draft }, set: { draft = $0 })
        let editor = try #require(RecordDraftBinding.make(source))
        editor.watchedSeasonText.wrappedValue = value
        editor.shortReview.wrappedValue = "继续填写短评"
        draft?.details.imdbRating = 9.5
        #expect(editor.wrappedValue.watchedSeasonText == value)
        #expect(editor.wrappedValue.watchedSeason == nil)
        #expect(editor.wrappedValue.validationMessage != nil)
        #expect(throws: RecordDraft.DraftError.self) { try editor.wrappedValue.makeRecord() }
    }

    @Test("有效季数在切换到短评后仍保留", arguments: ["2", " 12 ", "002", "２"])
    func validTextRemainsVisible(value: String) throws {
        var draft: RecordDraft? = RecordDraft(details: Fixtures.details(Fixtures.series))
        draft?.myRating = 8
        let source = Binding<RecordDraft?>(get: { draft }, set: { draft = $0 })
        let editor = try #require(RecordDraftBinding.make(source))
        editor.watchedSeasonText.wrappedValue = value
        editor.shortReview.wrappedValue = "填写短评后仍保留季数"
        #expect(editor.wrappedValue.watchedSeasonText == value)
        #expect(editor.wrappedValue.watchedSeason != nil)
        #expect(editor.wrappedValue.validationMessage == nil)
        #expect(try editor.wrappedValue.makeRecord().watchedSeason == (value.contains("12") ? 12 : 2))
    }

    @Test("无效数字保留原文且阻止保存旧的季数", arguments: ["", "0", "-2", "1.5", "2abc", "999999999999999999999999999999"])
    func invalidNumericInputCannotSave(value: String) {
        var draft = RecordDraft(details: Fixtures.details(Fixtures.series))
        draft.myRating = 8
        draft.watchedSeason = 3
        draft.watchedSeasonText = value
        #expect(draft.watchedSeasonText == value)
        #expect(draft.watchedSeason == nil)
        #expect(draft.seasonValidationMessage != nil)
        #expect(throws: RecordDraft.DraftError.self) { try draft.makeRecord() }
    }

    @Test("纠正为数字后可保存，重新打开数据库保留季数与短评")
    func correctedSeasonSurvivesReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MovieJournalSeasonTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try PersistenceController.makeContainer(in: directory)
        var draft = RecordDraft(details: Fixtures.details(Fixtures.series))
        draft.myRating = 9
        draft.watchedSeasonText = "第2季"
        #expect(draft.validationMessage != nil)
        draft.watchedSeasonText = "2"
        draft.shortReview = "看到第二季"
        #expect(draft.validationMessage == nil)
        try RecordStore(context: container.mainContext).insert(draft.makeRecord())
        let reopened = try PersistenceController.makeContainer(in: directory)
        let record = try #require(RecordStore(context: reopened.mainContext).recordsNewestFirst().first)
        #expect(record.watchedSeason == 2)
        #expect(record.shortReview == "看到第二季")
        #expect(record.myRating == 9)
    }
}
