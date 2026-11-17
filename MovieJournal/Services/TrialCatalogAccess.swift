import Foundation

nonisolated struct TrialCatalogConnection: Codable, Sendable {
    let server: URL
    let token: String
    let expiresAt: Int64

    var isExpired: Bool { Double(expiresAt) <= Date().timeIntervalSince1970 }

    static func serverURL(_ text: String) throws -> URL {
        guard var components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else { throw TrialCatalogError.invalidServer }
        components.path = ""
        guard let url = components.url else { throw TrialCatalogError.invalidServer }
        return url
    }
}

nonisolated enum TrialCatalogError: LocalizedError, Equatable, Sendable {
    case invalidServer, invalidInvitation, expiredSession

    var errorDescription: String? {
        switch self {
        case .invalidServer: "请输入试用服务的 HTTPS 地址。"
        case .invalidInvitation: "邀请码无效，请向邀请人确认。"
        case .expiredSession: "试用已到期或被撤销，请在设置里重新连接。"
        }
    }
}

actor TrialCatalogAccess {
    private let keychain: any KeychainStoring
    private let transport: any HTTPTransport

    init(keychain: any KeychainStoring, transport: any HTTPTransport = HTTPClient(followsRedirects: false)) {
        self.keychain = keychain
        self.transport = transport
    }

    func activate(server: String, invite: String) async throws -> TrialCatalogConnection {
        struct Invitation: Encodable { let code: String }
        struct Session: Decodable { let token: String; let expiresAt: Int64 }
        let base = try TrialCatalogConnection.serverURL(server)
        let code = invite.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { throw TrialCatalogError.invalidInvitation }
        var request = URLRequest(url: base.appending(path: "api/trial/session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Invitation(code: code))
        let response = try await transport.send(request)
        if response.statusCode == 401 || response.statusCode == 403 { throw TrialCatalogError.invalidInvitation }
        try APIRequest.check(response, provider: .trial)
        let issued = try APIRequest.decode(Session.self, from: response.data)
        let session = TrialCatalogConnection(server: base, token: issued.token, expiresAt: issued.expiresAt)
        let alphabet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        guard !session.token.isEmpty, session.token.count <= 173, !session.isExpired,
              session.token.unicodeScalars.allSatisfy(alphabet.contains) else { throw APIError.invalidResponse }
        let data = try JSONEncoder().encode(session)
        try await keychain.save(String(decoding: data, as: UTF8.self), for: .trial)
        return session
    }

    func savedConnection() async throws -> TrialCatalogConnection? {
        guard let stored = try await keychain.read(.trial) else { return nil }
        let connection = try APIRequest.decode(TrialCatalogConnection.self, from: Data(stored.utf8))
        _ = try TrialCatalogConnection.serverURL(connection.server.absoluteString)
        return connection
    }

    func selectedCatalog() async throws -> (TMDBClient, String)? {
        guard let connection = try await savedConnection() else { return nil }
        guard !connection.isExpired else { throw TrialCatalogError.expiredSession }
        return (TMDBClient(transport: transport, trialServer: connection.server), connection.token)
    }

    func disconnect() async throws { try await keychain.delete(.trial) }
}
