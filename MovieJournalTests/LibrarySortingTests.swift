import Foundation
import Testing
@testable import MovieJournal

@Suite("资料库片名与发行年份排序")
@MainActor
struct LibrarySortingTests {
    private func record(_ id: Int, _ title: String, year: Int? = nil,
                        type: MediaType = .movie, status: WatchStatus = .watched) -> ViewingRecord {
        ViewingRecord(tmdbID: id, mediaType: type, title: title, releaseYear: year,
                      watchStatus: status, createdAt: Date(timeIntervalSince1970: 100))
    }

    @Test("中文按拼音与英文混排，忽略片名开头的书名号和空格")
    func mixedChineseAndEnglishTitles() {
        let records = [record(1, "Zootopia"), record(2, "《霸王别姬》"), record(3, " 重庆森林 "),
                       record(4, "Batman"), record(5, "盗梦空间"), record(6, "阿凡达")]
        let model = LibraryViewModel()
        #expect(model.matchingRecords(in: records, sort: .titleAscending).map(\.tmdbID) == [6, 4, 2, 3, 5, 1])
        #expect(model.matchingRecords(in: records, sort: .titleDescending).map(\.tmdbID) == [1, 5, 3, 2, 4, 6])
    }

    @Test("数字使用自然顺序；大小写、重音和全角字符不影响字母顺序")
    func naturalNumbersAndNormalizedLetters() {
        let records = [record(1, "电影10"), record(2, "电影2"), record(3, "电影１"),
                       record(4, "éclair"), record(5, "ＢＡＴＭＡＮ"), record(6, "alien")]
        #expect(LibraryViewModel().matchingRecords(in: records, sort: .titleAscending).map(\.tmdbID) == [6, 5, 3, 2, 1, 4])
    }

    @Test("发行年份支持双向排序，同年按片名，缺失年份始终置后")
    func releaseYearAndUnknownYears() {
        let records = [record(1, "Zulu", year: 2000), record(2, "Alpha", year: 2000),
                       record(3, "老电影", year: 1954), record(4, "新电影", year: 2026),
                       record(5, "未知B"), record(6, "未知A")]
        let model = LibraryViewModel()
        #expect(model.matchingRecords(in: records, sort: .releaseNewest).map(\.tmdbID) == [4, 2, 1, 3, 6, 5])
        #expect(model.matchingRecords(in: records, sort: .releaseOldest).map(\.tmdbID) == [3, 2, 1, 4, 6, 5])
    }

    @Test("新排序同时遵守状态、媒体类型与搜索条件")
    func sortingRespectsCombinedFilters() {
        let records = [record(1, "电影B", year: 1990, status: .wantToWatch),
                       record(2, "电影A", year: 2020, status: .wantToWatch),
                       record(3, "电影C", year: 2025),
                       record(4, "电影剧集", year: 2026, type: .tv, status: .wantToWatch),
                       record(5, "无关片名", year: 2026, status: .wantToWatch)]
        let model = LibraryViewModel()
        model.mediaFilter = .movie
        model.statusFilter = .wantToWatch
        model.searchText = "电影"
        #expect(model.matchingRecords(in: records, sort: .titleAscending).map(\.tmdbID) == [2, 1])
        #expect(model.matchingRecords(in: records, sort: .releaseOldest).map(\.tmdbID) == [1, 2])
        #expect(model.matchingRecords(in: [], sort: .releaseNewest).isEmpty)
    }

    @Test("同名同年顺序稳定，无法生成首字母的片名始终置后")
    func deterministicTiesAndEmptyKeys() {
        let first = record(1, "Alien", year: 2000)
        let second = record(2, "alien", year: 2000)
        let punctuation = record(3, "？")
        let records = [punctuation, second, first]
        let model = LibraryViewModel()
        for sort in [LibrarySort.titleAscending, .titleDescending, .releaseNewest, .releaseOldest] {
            #expect(model.matchingRecords(in: records, sort: sort).map(\.tmdbID) == [1, 2, 3])
            #expect(model.matchingRecords(in: records.reversed(), sort: sort).map(\.tmdbID) == [1, 2, 3])
        }
    }
}
