import Foundation

nonisolated struct HTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
}

nonisolated protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

nonisolated enum APIError: LocalizedError, Equatable, Sendable {
    case missingKey(APIKeyProvider)
    case invalidKey(APIKeyProvider)
    case rateLimited(APIKeyProvider)
    case serviceUnavailable(APIKeyProvider)
    case networkUnavailable
    case timedOut
    case invalidResponse
    case notFound

    var errorDescription: String? {
        switch self {
        case .missingKey(let provider): "请先在设置中填写 \(provider.shortName) Key。"
        case .invalidKey(let provider): "\(provider.shortName) Key 无效或没有访问权限，请在设置中检查。"
        case .rateLimited(let provider): "\(provider.shortName) 请求次数已用完或过于频繁，请稍后重试。"
        case .serviceUnavailable(let provider): "\(provider.shortName) 服务暂时不可用，请稍后重试。"
        case .networkUnavailable: "网络连接失败，请检查网络后重试。"
        case .timedOut: "网络请求超时，请稍后重试。"
        case .invalidResponse: "服务返回的数据无法识别，请稍后重试。"
        case .notFound: "服务没有找到这部作品。"
        }
    }
}

actor HTTPClient: HTTPTransport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            return HTTPResponse(data: data, statusCode: response.statusCode)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            if error.code == .timedOut { throw APIError.timedOut }
            // 不传播带有请求 URL 的原始错误，防止查询参数中的 Key 出现在界面或日志中。
            throw APIError.networkUnavailable
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkUnavailable
        }
    }
}

nonisolated enum APIRequest {
    static func get(host: String, path: String, query: [URLQueryItem]) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = query
        guard let url = components.url else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func check(_ response: HTTPResponse, provider: APIKeyProvider) throws {
        switch response.statusCode {
        case 200..<300: return
        case 401, 403: throw APIError.invalidKey(provider)
        case 404: throw APIError.notFound
        case 429: throw APIError.rateLimited(provider)
        default: throw APIError.serviceUnavailable(provider)
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw APIError.invalidResponse }
    }
}
