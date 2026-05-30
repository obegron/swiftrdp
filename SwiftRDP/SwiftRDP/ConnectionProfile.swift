import Foundation

struct ConnectionProfile: Identifiable, Codable, Equatable {
    var id: String { "\(host)|\(port)|\(user)" }
    var host: String
    var port: Int32
    var user: String
    var lastUsed: Date
}

final class RecentConnectionStore: ObservableObject {
    @Published private(set) var profiles: [ConnectionProfile] = []

    private let defaultsKey = "recentConnections"
    private let maxProfiles = 12

    init() {
        load()
    }

    func touch(host: String, port: Int32, user: String) {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty, !normalizedUser.isEmpty else {
            return
        }

        let profile = ConnectionProfile(
            host: normalizedHost,
            port: port,
            user: normalizedUser,
            lastUsed: Date()
        )

        profiles.removeAll { $0.id == profile.id }
        profiles.insert(profile, at: 0)
        if profiles.count > maxProfiles {
            profiles.removeLast(profiles.count - maxProfiles)
        }
        save()
    }

    func remove(_ profile: ConnectionProfile) {
        profiles.removeAll { $0.id == profile.id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            profiles = []
            return
        }

        profiles = (try? JSONDecoder().decode([ConnectionProfile].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(profiles) else {
            return
        }

        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
