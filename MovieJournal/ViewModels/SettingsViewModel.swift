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
    private var hasLoaded = false
    private var inputs: [APIKeyProvider: String] = [:]
    private(set) var isWorking = false
    private(set) var statuses: [APIKeyProvider: KeyStatus] = [.tmdb: .checking, .omdb: .checking]
    private(set) var notices: [APIKeyProvider: Notice] = [:]

    init(keychain: any KeychainStoring) {
        self.keychain = keychain
    }

    func status(for provider: APIKeyProvider) -> KeyStatus {
        statuses[provider] ?? .checking
    }

    func input(for provider: APIKeyProvider) -> String {
        inputs[provider] ?? ""
    }

    func setInput(_ value: String, for provider: APIKeyProvider) {
        inputs[provider] = value
        notices[provider] = nil
    }

    func canSave(_ provider: APIKeyProvider) -> Bool {
        !isWorking && !input(for: provider).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func canDelete(_ provider: APIKeyProvider) -> Bool {
        !isWorking && status(for: provider) != .missing && status(for: provider) != .checking
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
                if status(for: provider) != newStatus { notices[provider] = nil }
                statuses[provider] = newStatus
            } catch {
                statuses[provider] = .unavailable(error.localizedDescription)
                notices[provider] = nil
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
        isWorking = true
        defer { isWorking = false }
        do {
            try await keychain.save(value, for: provider)
            statuses[provider] = .saved
            inputs[provider] = ""
            notices[provider] = .success("已保存到本机钥匙串，尚未联网验证。")
        } catch {
            // 保留输入和上次已知状态，允许重试；不会把失败解释成未配置。
            notices[provider] = .failure(error.localizedDescription)
        }
    }

    func delete(_ provider: APIKeyProvider) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await keychain.delete(provider)
            statuses[provider] = .missing
            inputs[provider] = ""
            notices[provider] = .success("已清除 \(provider.shortName) Key。")
        } catch {
            notices[provider] = .failure(error.localizedDescription)
        }
    }
}
