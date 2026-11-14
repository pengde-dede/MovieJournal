import SwiftUI

struct AddRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsViewModel.self) private var settings
    @State private var model: AddRecordViewModel
    @FocusState private var isSearchFocused: Bool
    @State private var pendingAction: (() -> Void)?
    @State private var confirmDiscard = false
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
                Button("取消") { protectDraft { dismiss() } }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            searchBar
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HSplitView {
                searchPane
                    .frame(minWidth: 220, idealWidth: 310, maxWidth: 360, maxHeight: .infinity, alignment: .top)
                detailsPane
                    .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let draft = model.draft {
                Divider()
                HStack {
                    Spacer()
                    Button("加入\(draft.watchStatus.title)") {
                        if let id = model.saveRecord() { openRecord(id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isSaving || draft.validationMessage != nil)
                }
                .padding(14)
            }
        }
        .frame(minWidth: 740, idealWidth: 920, maxWidth: 1100, minHeight: 500, idealHeight: 640, maxHeight: 860)
        .interactiveDismissDisabled(model.hasPersonalEdits)
        .alert("放弃未保存的观影信息？", isPresented: $confirmDiscard) {
            Button("继续填写", role: .cancel) { pendingAction = nil }
            Button("放弃更改", role: .destructive) { let action = pendingAction; pendingAction = nil; action?() }
        }
        .task { isSearchFocused = true }
        .onChange(of: model.searchMode) { _, _ in isSearchFocused = true }
        .onDisappear { model.cancelPendingWork() }
    }

    private func protectDraft(_ action: @escaping () -> Void) {
        if model.hasPersonalEdits {
            pendingAction = action
            confirmDiscard = true
        } else {
            action()
        }
    }

    private var searchBar: some View {
        @Bindable var model = model
        let isDirectorMode = model.searchMode == .director
        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                if model.canSearchByDirector {
                    Picker("搜索方式", selection: Binding(get: { model.searchMode }, set: { model.switchMode(to: $0) })) {
                        ForEach(AddRecordViewModel.SearchMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 130)
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(isDirectorMode ? "输入导演名字，例如：诺兰" : "输入电影或剧集片名", text: $model.query)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .onSubmit { protectDraft { model.search() } }
                        .accessibilityLabel(isDirectorMode ? "联网搜索导演" : "联网搜索片名")
                    if !model.query.isEmpty {
                        Button { model.query = ""; isSearchFocused = true } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("清空输入").accessibilityLabel("清空搜索输入")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSearchFocused ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: 1)
                }
                Button("搜索") { protectDraft { model.search() } }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .frame(maxWidth: 760)
            if settings.status(for: .tmdb) == .missing {
                HStack(spacing: 10) {
                    Text("请先在设置中填写 TMDB Key。")
                        .font(.callout).foregroundStyle(.secondary)
                    SettingsLink { Text("打开设置") }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    private var searchPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.searchMode == .director && model.selectedPerson == nil ? "人物候选" : "作品候选")
                .font(.headline)
                .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            searchResults
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var searchResults: some View {
        if model.isSearching {
            ProgressView("正在搜索…").controlSize(.small)
        } else if let error = model.searchError {
            failure(title: "搜索失败", message: error) { protectDraft { model.search() } }
        } else if model.searchMode == .director {
            directorResults.padding(16)
        } else if model.results.isEmpty {
            ContentUnavailableView(
                model.hasSearched ? "没有搜索结果" : "搜索电影和剧集",
                systemImage: "magnifyingglass",
                description: Text(model.hasSearched ? "没有找到相关电影或剧集，请尝试其他片名。" : "在上方输入片名，搜索后选择正确的作品。")
            )
        } else {
            List(model.results) { candidateButton($0) }
                .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var directorResults: some View {
        if let person = model.selectedPerson {
            VStack(alignment: .leading, spacing: 10) {
                Button { model.backToPeople() } label: { Label("返回人物列表", systemImage: "chevron.left") }
                    .buttonStyle(.link)
                Text("\(person.name) 的作品").font(.headline)
                if model.isLoadingWorks {
                    ProgressView("正在获取作品…")
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.worksError {
                    failure(title: "作品加载失败", message: error) { model.selectPerson(person) }
                } else if model.personWorks.isEmpty {
                    ContentUnavailableView("没有找到执导的作品", systemImage: "film",
                        description: Text("TMDB 上没有这位影人执导的电影或主创的剧集。"))
                } else {
                    List(model.personWorks) { work in
                        candidateButton(work.result, tags: [work.role.title] + (model.isSaved(work) ? ["已添加"] : []))
                    }
                    .listStyle(.plain)
                }
            }
        } else if model.personResults.isEmpty {
            ContentUnavailableView(
                model.hasSearched ? "没有找到相关人物" : "按导演搜索",
                systemImage: "person.crop.rectangle",
                description: Text(model.hasSearched ? "试试导演的其他译名或英文名。" : "输入导演名字，选中后会列出他执导的电影和主创的剧集。")
            )
        } else {
            List(model.personResults) { person in
                Button { model.selectPerson(person) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        SearchPosterView(path: person.profilePath).frame(width: 52)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(person.name).font(.headline).lineLimit(2)
                            Text(person.departmentTitle)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(person.isDirector ? Color.accentColor : Color.secondary)
                            if !person.knownFor.isEmpty {
                                Text(person.knownFor.joined(separator: "、"))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    private func candidateButton(_ candidate: MediaSearchResult, tags: [String] = []) -> some View {
        Button { protectDraft { model.select(candidate) } } label: {
            HStack(alignment: .top, spacing: 12) {
                SearchPosterView(path: candidate.posterPath).frame(width: 52)
                VStack(alignment: .leading, spacing: 8) {
                    Text(candidate.title).font(.headline).lineLimit(3)
                    Text("\(candidate.releaseYear.map(String.init) ?? "年份未知") · \(candidate.mediaType.title)")
                        .font(.caption).foregroundStyle(.secondary)
                    if !tags.isEmpty {
                        Text(tags.joined(separator: " · "))
                            .font(.caption.weight(.medium)).foregroundStyle(Color.accentColor)
                    }
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
                    Text(draft.wrappedValue.details.title).font(.title2.bold())
                    RecordEditorView(draft: draft)
                    DisclosureGroup("影片资料与平台评分") {
                        MediaInformationView(details: draft.wrappedValue.details, posterFilename: draft.wrappedValue.posterFilename)
                    }
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
                    if let error = model.saveError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
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
