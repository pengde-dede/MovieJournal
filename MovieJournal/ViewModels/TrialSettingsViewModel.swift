import Foundation
import Observation

@MainActor
@Observable
final class TrialSettingsViewModel {
    var server = Bundle.main.object(forInfoDictionaryKey: "MovieJournalTrialServer") as? String ?? ""
    var invite = ""
    private(set) var connection: TrialCatalogConnection?
    private(set) var isWorking = false
    private(set) var error: String?
    private let access: TrialCatalogAccess

    var isConnected: Bool { connection?.isExpired == false }

    init(access: TrialCatalogAccess) { self.access = access }

    func refresh() async {
        guard !isWorking else { return }
        do {
            connection = try await access.savedConnection()
            if let connection, server.isEmpty { server = connection.server.absoluteString }
        } catch { self.error = error.localizedDescription }
    }

    func activate() async {
        guard !isWorking else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            connection = try await access.activate(server: server, invite: invite)
            invite = ""
        } catch { self.error = error.localizedDescription }
    }

    func disconnect() async {
        guard !isWorking else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            try await access.disconnect()
            connection = nil
        } catch { self.error = error.localizedDescription }
    }
}
