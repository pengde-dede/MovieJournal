import Foundation
import Security

nonisolated protocol KeychainStoring: Sendable {
    func contains(_ provider: APIKeyProvider) async throws -> Bool
    func read(_ provider: APIKeyProvider) async throws -> String?
    func save(_ value: String, for provider: APIKeyProvider) async throws
    func delete(_ provider: APIKeyProvider) async throws
}

nonisolated enum KeychainError: LocalizedError, Equatable, Sendable {
    case status(OSStatus)
    case invalidStoredValue
    case emptyValue

    var errorDescription: String? {
        switch self {
        case .emptyValue:
            "请输入 Key。留空不会清除已保存的 Key。"
        case .invalidStoredValue:
            "已保存的 Key 无法读取，请在设置中重新保存。"
        case .status(let status):
            switch status {
            case errSecUserCanceled:
                "钥匙串操作已取消，您可以重新尝试。"
            case errSecAuthFailed:
                "钥匙串未授权访问。请允许本应用访问后重试。"
            case errSecInteractionNotAllowed:
                "钥匙串已锁定或暂时不允许访问，请解锁登录钥匙串后重试。"
            case errSecNotAvailable:
                "钥匙串暂时不可用，请稍后重试。"
            case errSecMissingEntitlement:
                "当前应用签名缺少钥匙串访问权限，请检查 Xcode 的签名设置。"
            default:
                "钥匙串操作失败（错误码 \(status)），请重试。"
            }
        }
    }
}

/// 用独立 actor 执行可能等待系统授权的操作，避免阻塞界面主线程。
actor KeychainService: KeychainStoring {
    nonisolated static let defaultServiceName = "io.github.pengde-dede.MovieJournal.api-keys"
    private let serviceName: String

    init(serviceName: String = KeychainService.defaultServiceName) {
        self.serviceName = serviceName
    }

    func contains(_ provider: APIKeyProvider) async throws -> Bool {
        var query = baseQuery(for: provider)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // 不请求 kSecReturnData。启动和检查状态时不读取密码内容。
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess: return true
        case errSecItemNotFound: return false
        default: throw KeychainError.status(status)
        }
    }

    /// 只在确实需要使用 Key 时读取；设置页不会把已保存的 Key 填回输入框。
    func read(_ provider: APIKeyProvider) async throws -> String? {
        var query = baseQuery(for: provider)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            throw KeychainError.invalidStoredValue
        }
        return value
    }

    func save(_ value: String, for provider: APIKeyProvider) async throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KeychainError.emptyValue
        }
        let query = baseQuery(for: provider)
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError.status(updateStatus) }

        var newItem = query
        newItem[kSecValueData as String] = Data(value.utf8)
        newItem[kSecAttrLabel as String] = "观影记录 · \(provider.shortName) API Key"
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        if addStatus == errSecSuccess { return }
        // 防止查找与新增之间有另一个实例创建了同一项；不会先删除旧 Key。
        if addStatus == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard retryStatus == errSecSuccess else { throw KeychainError.status(retryStatus) }
            return
        }
        throw KeychainError.status(addStatus)
    }

    func delete(_ provider: APIKeyProvider) async throws {
        let status = SecItemDelete(baseQuery(for: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    private func baseQuery(for provider: APIKeyProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: provider.account,
            kSecAttrSynchronizable as String: false
        ]
        // 使用默认的 macOS 文件钥匙串，兼容当前无 Team 的本地签名。
        // 不启用需要预置描述文件权限的 Data Protection / 跨应用访问组。
    }
}
