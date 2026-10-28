import Foundation

nonisolated enum KeyValidationResult: Equatable, Sendable {
    case valid
    case invalid
    case networkFailure(String)
    case unavailable(String)
}

nonisolated protocol APIKeyValidating: Sendable {
    func validate(_ provider: APIKeyProvider, key: String) async throws -> KeyValidationResult
}

nonisolated struct APIKeyValidator: APIKeyValidating {
    let tmdb: TMDBClient
    let omdb: OMDbClient
    init(tmdb: TMDBClient = TMDBClient(), omdb: OMDbClient = OMDbClient()) {
        self.tmdb = tmdb
        self.omdb = omdb
    }

    func validate(_ provider: APIKeyProvider, key: String) async throws -> KeyValidationResult {
        do {
            switch provider {
            case .tmdb: try await tmdb.authenticate(key: key)
            case .omdb: _ = try await omdb.ratings(imdbID: "tt0111161", key: key)
            }
            return .valid
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as APIError {
            switch error {
            case .invalidKey: return .invalid
            case .networkUnavailable, .timedOut: return .networkFailure(error.localizedDescription)
            default: return .unavailable(error.localizedDescription)
            }
        } catch {
            return .unavailable("暂时无法完成验证，请稍后重试。")
        }
    }
}
