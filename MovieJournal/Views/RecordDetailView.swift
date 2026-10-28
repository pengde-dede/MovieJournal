import SwiftData
import SwiftUI

struct RecordDetailDestinationView: View {
    @Query private var records: [ViewingRecord]

    init(recordID: UUID) {
        let identifier = recordID
        _records = Query(filter: #Predicate<ViewingRecord> { $0.id == identifier })
    }

    var body: some View {
        if let record = records.first { RecordDetailView(record: record) }
        else { ContentUnavailableView("没有找到这条记录", systemImage: "film") }
    }
}

struct RecordDetailView: View {
    let record: ViewingRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MediaInformationView(details: details, posterFilename: record.posterFilename)
                GroupBox("我的观影记录") {
                    VStack(alignment: .leading, spacing: 14) {
                        LabeledContent(record.mediaType == .tv ? "最近观看日期" : "观看日期") {
                            Text(record.watchedOn, format: .dateTime.year().month().day())
                        }
                        LabeledContent("我的评分", value: "\(record.myRating)/10")
                        if record.mediaType == .tv, let season = record.watchedSeason {
                            LabeledContent("观看进度", value: "看到第 \(season) 季")
                        }
                        Divider()
                        Text(record.shortReview.isEmpty ? "暂无短评" : record.shortReview)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(8)
                }
            }
            .frame(maxWidth: 1000)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(record.title)
        .textSelection(.enabled)
    }

    private var details: MediaDetails {
        MediaDetails(
            tmdbID: record.tmdbID, mediaType: record.mediaType,
            title: record.title, originalTitle: record.originalTitle, releaseYear: record.releaseYear,
            genres: record.genres, overview: record.overview, overviewLanguage: record.overviewLanguage,
            creatorNames: record.creatorNames, castNames: record.castNames,
            imdbID: record.imdbID, tmdbRating: record.tmdbRating, imdbRating: record.imdbRating,
            rottenTomatoesRating: record.rottenTomatoesRating, posterPath: record.posterPath,
            fetchedAt: record.metadataFetchedAt, informationNote: nil
        )
    }
}
