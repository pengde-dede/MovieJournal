import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    enum KeyStatus: Equatable {
        case checking
        case missing
        case saved
        case unavailable(String)
    }

    enum Notice: Equatable {
        case success(String)
        case failure(String)
        var message: String {
            switch self {
            case .success(let message), .failure(let message): message
            }
        }
        var isFailure: Bool {
            if case .failure = self { return true }
            return false
        }
    }

    private let keychain: any KeychainStoring
    private let validator: any APIKeyValidating
    private var hasLoaded = false
    private var inputs: [APIKeyProvider: String] = [:]
    private var validationRevisions: [APIKeyProvider: Int] = [:]
    @ObservationIgnored private var validationTasks: [APIKeyProvider: Task<Void, Never>] = [:]
    private(set) var isWorking = false
    private(set) var statuses: [APIKeyProvider: KeyStatus] = [.tmdb: .checking, .omdb: .checking]
    private(set) var notices: [APIKeyProvider: Notice] = [:]
    private(set) var warnings: [APIKeyProvider: String] = [:]
    private(set) var validationResults: [APIKeyProvider: KeyValidationResult] = [:]
    private(set) var validatingProviders = Set<APIKeyProvider>()

    init(keychain: any KeychainStoring, validator: any APIKeyValidating = APIKeyValidator()) {
        self.keychain = keychain
        self.validator = validator
    }

    func status(for provider: APIKeyProvider) -> KeyStatus { statuses[provider] ?? .checking }
    func input(for provider: APIKeyProvider) -> String { inputs[provider] ?? "" }

    func setInput(_ value: String, for provider: APIKeyProvider) {
        inputs[provider] = value
        notices[provider] = nil
        warnings[provider] = nil
        resetValidation(provider)
    }

    func canSave(_ provider: APIKeyProvider) -> Bool {
        !isWorking && !input(for: provider).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func canDelete(_ provider: APIKeyProvider) -> Bool {
        !isWorking && status(for: provider) != .missing && status(for: provider) != .checking
    }

    func canValidate(_ provider: APIKeyProvider) -> Bool {
        !isWorking && status(for: provider) == .saved && !validatingProviders.contains(provider)
            && input(for: provider).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func refreshIfNeeded() async {
        guard !hasLoaded else { return }
        await refresh()
    }

    func refresh() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        for provider in APIKeyProvider.allCases {
            do {
                let exists = try await keychain.contains(provider)
                let newStatus: KeyStatus = exists ? .saved : .missing
                if status(for: provider) != newStatus {
                    notices[provider] = nil
                    resetValidation(provider)
                }
                statuses[provider] = newStatus
            } catch {
                statuses[provider] = .unavailable(error.localizedDescription)
                notices[provider] = nil
                resetValidation(provider)
            }
        }
        hasLoaded = true
    }

    func save(_ provider: APIKeyProvider) async {
        guard !isWorking else { return }
        let value = input(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            notices[provider] = .failure(KeychainError.emptyValue.localizedDescription)
            return
        }
        resetValidation(provider)
        warnings[provider] = Self.tokenWarning(value, provider: provider)
        isWorking = true
        defer { isWorking = false }
        do {
            try await keychain.save(value, for: provider)
            statuses[provider] = .saved
            inputs[provider] = ""
            notices[provider] = .success("已保存到本机钥匙串。")
        } catch {
            notices[provider] = .failure(error.localizedDescription)
        }
    }

    func delete(_ provider: APIKeyProvider) async {
        guard !isWorking else { return }
        resetValidation(provider)
        isWorking = true
        defer { isWorking = false }
        do {
            try await keychain.delete(provider)
            statuses[provider] = .missing
            inputs[provider] = ""
            warnings[provider] = nil
            notices[provider] = .success("已清除 \(provider.shortName) Key。")
        } catch {
            notices[provider] = .failure(error.localizedDescription)
        }
    }

    @discardableResult
    func validate(_ provider: APIKeyProvider) -> Task<Void, Never> {
        guard canValidate(provider) else { return Task {} }
        resetValidation(provider)
        let revision = validationRevisions[provider, default: 0]
        validatingProviders.insert(provider)
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                guard let key = try await keychain.read(provider).nonEmpty else {
                    throw APIError.missingKey(provider)
                }
                try Task.checkCancellation()
                let result = try await validator.validate(provider, key: key)
                guard !Task.isCancelled, validationRevisions[provider] == revision else { return }
                validationResults[provider] = result
            } catch {
                guard !Task.isCancelled, validationRevisions[provider] == revision else { return }
                validationResults[provider] = .unavailable(error.localizedDescription)
                if error as? APIError == .missingKey(provider) { statuses[provider] = .missing }
            }
            guard validationRevisions[provider] == revision else { return }
            validatingProviders.remove(provider)
            validationTasks[provider] = nil
        }
        validationTasks[provider] = task
        return task
    }

    private func resetValidation(_ provider: APIKeyProvider) {
        validationRevisions[provider, default: 0] += 1
        validationTasks[provider]?.cancel()
        validationTasks[provider] = nil
        validationResults[provider] = nil
        validatingProviders.remove(provider)
    }

    static func tokenWarning(_ value: String, provider: APIKeyProvider) -> String? {
        guard provider == .tmdb, value.hasPrefix("eyJ") || value.count > 64 else { return nil }
        return "这看起来是 Read Access Token，请填写较短的 API Key（v3）"
    }
}
