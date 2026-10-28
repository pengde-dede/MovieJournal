import Foundation
import Testing
@testable import MovieJournal

@Suite("Key 验证与格式提示")
@MainActor
struct SettingsValidationTests {
    @Test("验证使用已保存值，结果不写入钥匙串且重建页面状态后消失")
    func validationIsTransient() async throws {
        let keychain = MemoryKeychain([.tmdb: "fake-saved"])
        let validator = FixedValidator(result: .valid)
        let model = SettingsViewModel(keychain: keychain, validator: validator)
        await model.refresh()
        await model.validate(.tmdb).value
        #expect(model.validationResults[.tmdb] == .valid)
        #expect(model.status(for: .tmdb) == .saved)
        #expect(await keychain.value(.tmdb) == "fake-saved")
        #expect(await validator.keys == ["fake-saved"])
        let reopened = SettingsViewModel(keychain: keychain, validator: validator)
        await reopened.refresh()
        #expect(reopened.validationResults.isEmpty)
        #expect(reopened.status(for: .tmdb) == .saved)
    }

    @Test("Token 开头或明显过长只提示，仍会保存", arguments: ["eyJ-test-token", String(repeating: "x", count: 65)])
    func tokenWarningDoesNotBlockSaving(value: String) async {
        let keychain = MemoryKeychain()
        let model = SettingsViewModel(keychain: keychain)
        await model.refresh()
        model.setInput(value, for: .tmdb)
        await model.save(.tmdb)
        #expect(await keychain.value(.tmdb) == value)
        #expect(model.status(for: .tmdb) == .saved)
        #expect(model.warnings[.tmdb] == "这看起来是 Read Access Token，请填写较短的 API Key（v3）")
        #expect(model.input(for: .tmdb).isEmpty)
    }

    @Test("换回较短 API Key 会清除旧提示，OMDb 不使用此提示规则")
    func normalKeyClearsTokenWarning() async {
        let keychain = MemoryKeychain()
        let model = SettingsViewModel(keychain: keychain)
        model.setInput("eyJ-test", for: .tmdb)
        await model.save(.tmdb)
        model.setInput(String(repeating: "a", count: 32), for: .tmdb)
        await model.save(.tmdb)
        #expect(model.warnings[.tmdb] == nil)
        model.setInput(String(repeating: "b", count: 100), for: .omdb)
        await model.save(.omdb)
        #expect(model.warnings[.omdb] == nil)
    }

    @Test("有未保存输入时不验证旧 Key，清除后也不能验证")
    func unsavedInputDoesNotValidateOldKey() async {
        let keychain = MemoryKeychain([.tmdb: "fake-old"])
        let validator = FixedValidator(result: .valid)
        let model = SettingsViewModel(keychain: keychain, validator: validator)
        await model.refresh()
        model.setInput("fake-new", for: .tmdb)
        #expect(!model.canValidate(.tmdb))
        await model.validate(.tmdb).value
        #expect(await validator.keys.isEmpty)
        await model.delete(.tmdb)
        #expect(!model.canValidate(.tmdb))
    }

    @Test("验证中的旧响应不会覆盖新输入的状态")
    func staleValidationIsDiscarded() async {
        let keychain = MemoryKeychain([.tmdb: "fake-old"])
        let validator = SuspendedValidator()
        let model = SettingsViewModel(keychain: keychain, validator: validator)
        await model.refresh()
        let task = model.validate(.tmdb)
        await validator.waitUntilStarted()
        model.setInput("fake-new", for: .tmdb)
        await validator.finish()
        await task.value
        #expect(model.validationResults[.tmdb] == nil)
        #expect(!model.validatingProviders.contains(.tmdb))
        #expect(model.input(for: .tmdb) == "fake-new")
    }
}

private actor FixedValidator: APIKeyValidating {
    let result: KeyValidationResult
    private(set) var keys: [String] = []
    init(result: KeyValidationResult) { self.result = result }
    func validate(_ provider: APIKeyProvider, key: String) async throws -> KeyValidationResult {
        keys.append(key)
        return result
    }
}

private actor SuspendedValidator: APIKeyValidating {
    private var continuation: CheckedContinuation<KeyValidationResult, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    func validate(_ provider: APIKeyProvider, key: String) async throws -> KeyValidationResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            startWaiter?.resume()
            startWaiter = nil
        }
    }
    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func finish() { continuation?.resume(returning: .valid); continuation = nil }
}
