import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import MovieJournal

@Suite("添加窗口搜索栏位置", .serialized)
@MainActor
struct AddRecordLayoutTests {
    @Test("片名和导演搜索均位于顶部居中，Key 提示不挤压搜索区", arguments: [true, false])
    func searchFieldIsNearTopAndCenter(keyConfigured: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MovieJournalLayoutTests-\(UUID().uuidString)", isDirectory: true)
        let container = try PersistenceController.makeContainer(in: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = SettingsViewModel(keychain: MemoryKeychain(keyConfigured ? [.tmdb: "fake-tmdb"] : [:]))
        await settings.refresh()
        let content = AddRecordView(catalog: LayoutCatalog(), store: RecordStore(context: container.mainContext), posters: StubPosterCache()) { _ in }
            .environment(settings)
            .environment(\.locale, Locale(identifier: "zh_CN"))
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 740),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "添加窗口布局验证"
        window.contentView = host
        defer { window.close() }
        host.setFrameSize(NSSize(width: 1040, height: 740))
        // 只创建不可见的假数据托管窗口，不操控用户已有窗口或发出真实请求。
        settleLayout(host)
        try checkSearchPosition(placeholder: "输入电影或剧集片名", in: host)
        let split = try #require(descendants(of: host).compactMap { $0 as? NSSplitView }.first)
        #expect(split.bounds.height > 400, "候选与详情区域应占满剩余高度，实际只有 \(split.bounds.height) 点")

        let picker = try #require(descendants(of: host).compactMap { $0 as? NSSegmentedControl }.first)
        picker.selectedSegment = 1
        picker.sendAction(picker.action, to: picker.target)
        settleLayout(host)
        try checkSearchPosition(placeholder: "输入导演名字，例如：诺兰", in: host)
    }

    private func checkSearchPosition(placeholder: String, in host: NSView) throws {
        let field = try #require(descendants(of: host).compactMap { $0 as? NSTextField }
            .first { $0.placeholderString == placeholder })
        let frame = field.convert(field.bounds, to: host)
        let distanceFromTop = host.isFlipped ? frame.minY : host.bounds.height - frame.maxY
        #expect(distanceFromTop < 180, "搜索框应位于窗口上方，实际距顶部 \(distanceFromTop) 点")
        #expect(abs(frame.midX - host.bounds.midX) < 100, "搜索框应水平居中，实际中心 x=\(frame.midX)")
        #expect(frame.minX >= 0 && frame.maxX <= host.bounds.width)
        if #available(macOS 26.0, *) {
            Attachment.record("\(placeholder): top=\(distanceFromTop), frame=\(frame), host=\(host.bounds)", named: "SearchField-position.txt")
        }
    }

    private func settleLayout(_ host: NSView) {
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

private nonisolated struct LayoutCatalog: MediaCatalogServing, PersonCatalogServing {
    func search(title: String) async throws -> [MediaSearchResult] { [] }
    func details(for candidate: MediaSearchResult) async throws -> MediaDetails { Fixtures.details(candidate) }
    func supplementalRatings(imdbID: String?) async throws -> SupplementalRatingsResult { .notConfigured }
    func searchPeople(name: String) async throws -> [PersonSearchResult] { [] }
    func directedWorks(personID: Int) async throws -> [CreditedWork] { [] }
}
