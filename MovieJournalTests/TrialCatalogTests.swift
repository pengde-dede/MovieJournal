import Foundation
import Testing
@testable import MovieJournal

@Suite("好友试用影片资料")
struct TrialCatalogTests {
    @Test func invitationEnablesSearchWithoutPersonalKey() async throws {
        let transport = ScriptedTransport([
            .json(#"{"token":"fixture-session","expiresAt":4102444800}"#),
            .json(#"{"results":[{"id":278,"media_type":"movie","title":"肖申克的救赎"}]}"#),
            .json(try Fixtures.movieJSON())
        ])
        let keychain = MemoryKeychain()
        let access = TrialCatalogAccess(keychain: keychain, transport: transport)
        _ = try await access.activate(server: "https://trial.example.test/", invite: "invitation-fixture")
        let catalog = MediaCatalogService(keychain: keychain, trial: access)
        let candidates = try await catalog.search(title: "C++ & 救赎")
        let match = try #require(candidates.first)
        #expect(try await catalog.details(for: match).tmdbID == 278)
        let requests = await transport.requests
        #expect(requests.map { $0.url?.path } == ["/api/trial/session", "/api/catalog/3/search/multi", "/api/catalog/3/movie/278"])
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer fixture-session")
        #expect(requests[1].url?.query?.contains("api_key") == false)
        #expect(requests[1].url?.absoluteString.contains("query=C%2B%2B%20%26%20") == true)
        #expect(await keychain.value(.tmdb) == nil)
        try await access.disconnect()
        await #expect(throws: APIError.missingKey(.tmdb)) { try await catalog.search(title: "电影") }
    }

    @Test func expiredOrRevokedSessionShowsTrialError() async throws {
        let transport = ScriptedTransport([
            .json(#"{"token":"fixture-session","expiresAt":4102444800}"#), .json("{}", status: 401)
        ])
        let keychain = MemoryKeychain([.tmdb: "personal-fixture"])
        let access = TrialCatalogAccess(keychain: keychain, transport: transport)
        _ = try await access.activate(server: "https://trial.example.test", invite: "invitation-fixture")
        let catalog = MediaCatalogService(keychain: keychain, trial: access)
        await #expect(throws: TrialCatalogError.expiredSession) { try await catalog.search(title: "电影") }
    }

    @Test func invitationRequiresUnambiguousHTTPSDestination() async {
        let transport = ScriptedTransport([])
        let access = TrialCatalogAccess(keychain: MemoryKeychain(), transport: transport)
        for server in ["http://example.test", "https://example.test/api", "https://name@example.test", "https://example.test/?token=x"] {
            await #expect(throws: TrialCatalogError.invalidServer) { try await access.activate(server: server, invite: "invite") }
        }
        #expect(await transport.requests.isEmpty)
    }
}
