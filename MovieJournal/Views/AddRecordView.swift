import SwiftUI

struct AddRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsViewModel.self) private var settings
    @State private var model: AddRecordViewModel
    let openRecord: (UUID) -> Void

    init(catalog: any MediaCatalogServing, store: RecordStore, posters: any PosterCaching, openRecord: @escaping (UUID) -> Void) {
        _model = State(initialValue: AddRecordViewModel(catalog: catalog, store: store, posters: posters))
        self.openRecord = openRecord
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("添加观影记录").font(.title2.bold())
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider()
            HSplitView {
                searchPane.frame(minWidth: 270, idealWidth: 310, maxWidth: 360)
                detailsPane.frame(minWidth: 570)
            }
        }
        .frame(width: 1040, height: 740)
        .onDisappear { model.cancelPendingWork() }
    }

    private var searchPane: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("输入电影或剧集片名", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.search() }
                    .accessibilityLabel("联网搜索片名")
                Button("搜索") { model.search() }
                    .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if settings.status(for: .tmdb) == .missing {
                Text("请先在设置中填写 TMDB Key。")
                    .font(.callout).foregroundStyle(.secondary)
                SettingsLink { Text("打开设置") }
            }
            if model.isSearching {
                ProgressView("正在搜索…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.searchError {
                failure(title: "搜索失败", message: error) { model.search() }
            } else if model.results.isEmpty {
                ContentUnavailableView(
                    model.hasSearched ? "没有搜索结果" : "搜索电影和剧集",
                    systemImage: "magnifyingglass",
                    description: Text(model.hasSearched ? "没有找到相关电影或剧集，请尝试其他片名。" : "输入片名，搜索后选择正确的作品。")
                )
            } else {
                List(model.results) { candidate in
                    Button { model.select(candidate) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            PosterView(path: candidate.posterPath, small: true).frame(width: 52)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(candidate.title).font(.headline).lineLimit(3)
                                Text("\(candidate.releaseYear.map(String.init) ?? "年份未知") · \(candidate.mediaType.title)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(model.selectedResult?.id == candidate.id ? Color.accentColor.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var detailsPane: some View {
        @Bindable var model = model
        if let id = model.duplicateRecordID {
            ContentUnavailableView {
                Label("这部作品已经添加", systemImage: "checkmark.circle")
            } description: {
                Text("已有记录会保留，可以直接打开查看。")
            } actions: {
                Button("打开已有记录") { openRecord(id) }
                    .buttonStyle(.borderedProminent)
            }
        } else if model.isLoadingDetails {
            ProgressView("正在获取影片资料…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.detailsError {
            failure(title: "资料加载失败", message: error) {
                if let candidate = model.selectedResult { model.select(candidate) }
            }
            .padding()
        } else if let draft = RecordDraftBinding.make($model.draft) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MediaInformationView(details: draft.wrappedValue.details, posterFilename: draft.wrappedValue.posterFilename)
                    if model.isLoadingSupplemental {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("正在获取补充评分，您也可以直接保存。")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    } else if let message = model.supplementalMessage {
                        Text(message).font(.callout).foregroundStyle(.secondary)
                    }
                    if model.isLoadingPoster {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("正在将海报保存到本机…").font(.callout).foregroundStyle(.secondary)
                        }
                    } else if let message = model.posterMessage {
                        Text(message).font(.callout).foregroundStyle(.secondary)
                        Button("重试海报") { model.retryPoster() }
                    }
                    RecordEditorView(draft: draft)
                    if let error = model.saveError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Spacer()
                        Button("保存观影记录") {
                            if let id = model.saveRecord() { openRecord(id) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isSaving || model.isLoadingPoster || draft.wrappedValue.validationMessage != nil)
                    }
                }
                .padding(24)
            }
        } else {
            ContentUnavailableView("选择正确的作品", systemImage: "film", description: Text("从左侧候选中选择后，会自动填写影片资料。"))
        }
    }

    private func failure(title: String, message: String, retry: @escaping () -> Void) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重试", action: retry)
            SettingsLink { Text("打开设置") }
        }
    }
}
