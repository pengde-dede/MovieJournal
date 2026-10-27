import Foundation
import Testing
@testable import MovieJournal

@Suite("本机钥匙串")
@MainActor
struct KeychainServiceTests {
    @Test("真实钥匙串支持保存、独立实例读取、更换、分别清除与重复清除")
    func localKeychainRoundTrip() async throws {
        // 只操作随机测试命名空间与假字符串，不读取或改动用户填写的 API Key。
        let serviceName = "io.github.pengde-dede.MovieJournal.tests.\(UUID().uuidString)"
        let store = KeychainService(serviceName: serviceName)
        let firstValue = "test-only-\(UUID().uuidString)"
        let replacement = "test-only-\(UUID().uuidString)"
        let supplementalValue = "test-only-\(UUID().uuidString)"

        do {
            #expect(try await !store.contains(.tmdb))
            #expect(try await store.read(.tmdb) == nil)
            try await store.save(firstValue, for: .tmdb)
            try await store.save(supplementalValue, for: .omdb)
            #expect(try await store.contains(.tmdb))
            #expect(try await store.contains(.omdb))

            let reopened = KeychainService(serviceName: serviceName)
            #expect(try await reopened.read(.tmdb) == firstValue)
            #expect(try await reopened.read(.omdb) == supplementalValue)
            try await reopened.save(replacement, for: .tmdb)
            #expect(try await store.read(.tmdb) == replacement)
            #expect(try await store.read(.omdb) == supplementalValue)

            // 空白不能意外覆盖已保存值。
            do {
                try await store.save("  \n", for: .tmdb)
                Issue.record("空白 Key 应被拒绝")
            } catch {
                #expect(error as? KeychainError == .emptyValue)
            }
            #expect(try await store.read(.tmdb) == replacement)
            try await store.delete(.tmdb)
            #expect(try await !reopened.contains(.tmdb))
            #expect(try await reopened.read(.tmdb) == nil)
            #expect(try await reopened.read(.omdb) == supplementalValue)
            try await store.delete(.tmdb)
        } catch {
            // await 完成清理，避免 defer 中启动未等待的 Task 留下测试条目。
            try? await store.delete(.tmdb)
            try? await store.delete(.omdb)
            throw error
        }
        try await store.delete(.omdb)
        #expect(try await !store.contains(.omdb))
    }
}
