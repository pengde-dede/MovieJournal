import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import MovieJournal

@Suite("添加表单切换安全性")
@MainActor
struct RecordDraftBindingTests {
    @Test("已有表单再次搜索时，旧表单仍可读取且不会恢复已清除的草稿")
    func searchingAgainKeepsRetiringEditorSafe() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MovieJournalDraftBindingTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try PersistenceController.makeContainer(in: directory)
        let catalog = MediaCatalogService(
            keychain: MemoryKeychain([.tmdb: "fake-tmdb"]),
            tmdb: TMDBClient(transport: ScriptedTransport([.json(#"{"results":[]}"#)]))
        )
        let model = AddRecordViewModel(catalog: catalog, store: RecordStore(context: container.mainContext), posters: StubPosterCache())
        model.draft = RecordDraft(details: Fixtures.details(Fixtures.series))
        let source = Binding<RecordDraft?>(get: { model.draft }, set: { model.draft = $0 })
        let editor = try #require(RecordDraftBinding.make(source))
        let retiringReview = editor.shortReview

        model.query = "七武士"
        await model.search().value
        #expect(model.draft == nil)
        #expect(editor.wrappedValue.details.tmdbID == Fixtures.series.tmdbID)
        retiringReview.wrappedValue = "旧输入事件晚到"
        #expect(model.draft == nil)
    }

    @Test("当前表单可以编辑，补充评分更新也能传到同一表单")
    func currentEditorKeepsEditsAndMetadataUpdates() throws {
        var draft: RecordDraft? = RecordDraft(details: Fixtures.details(Fixtures.series))
        let source = Binding<RecordDraft?>(get: { draft }, set: { draft = $0 })
        let editor = try #require(RecordDraftBinding.make(source))
        let identifier = editor.wrappedValue.editingID
        editor.myRating.wrappedValue = 8
        editor.watchedSeason.wrappedValue = 2
        editor.shortReview.wrappedValue = "正在看第二季"
        draft?.details.imdbRating = 9.5
        #expect(draft?.myRating == 8)
        #expect(draft?.watchedSeason == 2)
        #expect(draft?.shortReview == "正在看第二季")
        #expect(editor.wrappedValue.details.imdbRating == 9.5)
        #expect(editor.wrappedValue.editingID == identifier)
    }

    @Test("新草稿出现后，旧表单读写不会串到新草稿", arguments: [true, false])
    func retiringEditorCannotOverwriteReplacement(sameWork: Bool) throws {
        var draft: RecordDraft? = RecordDraft(details: Fixtures.details(Fixtures.series))
        let source = Binding<RecordDraft?>(get: { draft }, set: { draft = $0 })
        let oldEditor = try #require(RecordDraftBinding.make(source))
        let oldReview = oldEditor.shortReview
        draft = RecordDraft(details: Fixtures.details(sameWork ? Fixtures.series : Fixtures.movie))
        draft?.shortReview = "新草稿"
        let newEditor = try #require(RecordDraftBinding.make(source))
        #expect(oldEditor.wrappedValue.editingID != newEditor.wrappedValue.editingID)
        #expect(oldEditor.wrappedValue.details.tmdbID == Fixtures.series.tmdbID)
        oldReview.wrappedValue = "旧输入事件晚到"
        #expect(draft?.shortReview == "新草稿")
        newEditor.shortReview.wrappedValue = "新表单正常编辑"
        #expect(draft?.shortReview == "新表单正常编辑")
        #expect(draft?.details.tmdbID == (sameWork ? Fixtures.series.tmdbID : Fixtures.movie.tmdbID))
    }
}
