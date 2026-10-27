import Foundation
import Security
import Testing
@testable import MovieJournal

@Suite("API Key 设置")
@MainActor
struct SettingsViewModelTests {
    @Test("刷新状态只查存在性，不读取已保存的密码")
    func refreshDoesNotReadSecrets() async {
        let storage = FakeKeychain(values: [.tmdb: "fake-tmdb-value"])
        let model = SettingsViewModel(keychain: storage)
        await model.refreshIfNeeded()
        await model.refreshIfNeeded()

        #expect(model.status(for: .tmdb) == .saved)
        #expect(model.status(for: .omdb) == .missing)
        #expect(model.input(for: .tmdb).isEmpty)
        #expect(await storage.readCount == 0)
        #expect(await storage.containsCount == 2)
    }

    @Test("保存去掉首尾空白，清空输入，并且不改变另一把 Key")
    func saveTrimsInputWithoutChangingOtherProvider() async {
        let storage = FakeKeychain(values: [.omdb: "fake-omdb-old"])
        let model = SettingsViewModel(keychain: storage)
        await model.refresh()
        model.setInput("  fake-tmdb-new\n", for: .tmdb)
        await model.save(.tmdb)

        #expect(await storage.value(for: .tmdb) == "fake-tmdb-new")
        #expect(await storage.value(for: .omdb) == "fake-omdb-old")
        #expect(model.status(for: .tmdb) == .saved)
        #expect(model.input(for: .tmdb).isEmpty)
        #expect(model.notices[.tmdb] == .success("已保存到本机钥匙串，尚未联网验证。"))
        #expect(!model.isWorking)

        let reopened = SettingsViewModel(keychain: storage)
        await reopened.refresh()
        #expect(reopened.status(for: .tmdb) == .saved)
        #expect(reopened.status(for: .omdb) == .saved)
        #expect(reopened.input(for: .tmdb).isEmpty)
    }

    @Test("空白输入不清除旧 Key，也不调用保存接口")
    func blankInputPreservesSavedKey() async {
        let storage = FakeKeychain(values: [.tmdb: "fake-original"])
        let model = SettingsViewModel(keychain: storage)
        await model.refresh()
        model.setInput(" \n ", for: .tmdb)
        #expect(!model.canSave(.tmdb))
        await model.save(.tmdb)

        #expect(await storage.value(for: .tmdb) == "fake-original")
        #expect(await storage.saveCount == 0)
        #expect(model.status(for: .tmdb) == .saved)
        #expect(model.notices[.tmdb]?.isFailure == true)
    }

    @Test("更换失败时保留旧 Key、输入和已保存状态")
    func failedReplacementCanBeRetried() async {
        let storage = FakeKeychain(values: [.tmdb: "fake-original"])
        let model = SettingsViewModel(keychain: storage)
        await model.refresh()
        model.setInput("fake-replacement", for: .tmdb)
        await storage.setSaveError(.status(errSecAuthFailed))
        await model.save(.tmdb)

        #expect(await storage.value(for: .tmdb) == "fake-original")
        #expect(model.input(for: .tmdb) == "fake-replacement")
        #expect(model.status(for: .tmdb) == .saved)
        #expect(model.notices[.tmdb]?.isFailure == true)
        #expect(!model.isWorking)

        await storage.setSaveError(nil)
        await model.save(.tmdb)
        #expect(await storage.value(for: .tmdb) == "fake-replacement")
        #expect(model.input(for: .tmdb).isEmpty)
    }

    @Test("清除一把 Key 后，另一把 Key 仍保留")
    func deleteOnlyAffectsChosenProvider() async {
        let storage = FakeKeychain(values: [.tmdb: "fake-tmdb", .omdb: "fake-omdb"])
        let model = SettingsViewModel(keychain: storage)
        await model.refresh()
        await model.delete(.omdb)

        #expect(model.status(for: .omdb) == .missing)
        #expect(await storage.value(for: .omdb) == nil)
        #expect(await storage.value(for: .tmdb) == "fake-tmdb")
        #expect(model.status(for: .tmdb) == .saved)
        #expect(!model.canDelete(.omdb))
    }

    @Test("用户取消清除时，旧 Key 和输入都保留")
    func cancelledDeletePreservesState() async {
        let storage = FakeKeychain(values: [.tmdb: "fake-original"])
        let model = SettingsViewModel(keychain: storage)
        await model.refresh()
        model.setInput("fake-draft", for: .tmdb)
        await storage.setDeleteError(.status(errSecUserCanceled))
        await model.delete(.tmdb)

        #expect(await storage.value(for: .tmdb) == "fake-original")
        #expect(model.status(for: .tmdb) == .saved)
        #expect(model.input(for: .tmdb) == "fake-draft")
        #expect(model.notices[.tmdb]?.isFailure == true)
        #expect(!model.isWorking)
    }

    @Test("钥匙串访问失败不显示成未配置，恢复后可以重新检查")
    func statusFailureIsDistinctFromMissing() async {
        let storage = FakeKeychain(values: [.tmdb: "fake-original"])
        await storage.setContainsError(.status(errSecInteractionNotAllowed))
        let model = SettingsViewModel(keychain: storage)
        await model.refresh()

        if case .unavailable(let message) = model.status(for: .tmdb) {
            #expect(!message.isEmpty)
        } else {
            Issue.record("访问失败应显示错误，不能显示未配置或已保存")
        }
        #expect(!model.isWorking)
        await storage.setContainsError(nil)
        await model.refresh()
        #expect(model.status(for: .tmdb) == .saved)
        #expect(model.status(for: .omdb) == .missing)
        #expect(await storage.readCount == 0)
    }
}

private actor FakeKeychain: KeychainStoring {
    private var values: [APIKeyProvider: String]
    private var saveError: KeychainError?
    private var deleteError: KeychainError?
    private var containsError: KeychainError?
    private(set) var readCount = 0
    private(set) var containsCount = 0
    private(set) var saveCount = 0

    init(values: [APIKeyProvider: String] = [:]) {
        self.values = values
    }

    func contains(_ provider: APIKeyProvider) async throws -> Bool {
        containsCount += 1
        if let containsError { throw containsError }
        return values[provider] != nil
    }

    func read(_ provider: APIKeyProvider) async throws -> String? {
        readCount += 1
        return values[provider]
    }

    func save(_ value: String, for provider: APIKeyProvider) async throws {
        saveCount += 1
        if let saveError { throw saveError }
        values[provider] = value
    }

    func delete(_ provider: APIKeyProvider) async throws {
        if let deleteError { throw deleteError }
        values[provider] = nil
    }

    func value(for provider: APIKeyProvider) -> String? { values[provider] }
    func setSaveError(_ error: KeychainError?) { saveError = error }
    func setDeleteError(_ error: KeychainError?) { deleteError = error }
    func setContainsError(_ error: KeychainError?) { containsError = error }
}
