import Foundation

@MainActor
final class SettingsStore {
    private static let defaultsKey = "getkbd.settings"

    private let defaults: UserDefaults
    private(set) var value: AppSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode(AppSettings.self, from: data) {
            value = stored
        } else {
            value = .initial
        }
    }

    func replace(_ newValue: AppSettings) {
        value = newValue

        guard let data = try? JSONEncoder().encode(newValue) else {
            GetKbdLog.error("settings.save.failed", "Unable to encode settings")
            return
        }

        defaults.set(data, forKey: Self.defaultsKey)
    }
}
