import Foundation

@MainActor
final class PeerStore {
    private static let defaultsKey = "getkbd.peer"

    private let defaults: UserDefaults
    private(set) var value: PeerPreferences

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode(PeerPreferences.self, from: data) {
            value = stored
        } else {
            value = .initial()
        }
    }

    func replace(_ newValue: PeerPreferences) {
        value = newValue

        guard let data = try? JSONEncoder().encode(newValue) else {
            GetKbdLog.error("peer.settings.save.failed", "Unable to encode peer settings")
            return
        }

        defaults.set(data, forKey: Self.defaultsKey)
    }
}
