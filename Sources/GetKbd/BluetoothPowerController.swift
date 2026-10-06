import Darwin
import Foundation
@preconcurrency import IOBluetooth

/// Keep the undocumented power setter isolated and optional so an OS change can
/// fall back to System Settings rather than preventing the app from launching.
@MainActor
final class BluetoothPowerController {
    private let requestPowerOn: () -> Bool
    private let availability: () -> BluetoothAvailability
    private let timeout: Duration

    init(
        timeout: Duration = .seconds(10),
        requestPowerOn: (() -> Bool)? = nil,
        availability: (() -> BluetoothAvailability)? = nil
    ) {
        self.timeout = timeout
        self.requestPowerOn = requestPowerOn ?? Self.requestSystemPowerOn
        self.availability = availability ?? Self.systemAvailability
    }

    func enable() async -> Bool {
        guard !Task.isCancelled else { return false }
        if availability() == .poweredOn { return true }
        guard requestPowerOn() else { return false }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !Task.isCancelled {
            if availability() == .poweredOn { return true }
            guard clock.now < deadline else { return false }
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return false
            }
        }
        return false
    }

    private static func systemAvailability() -> BluetoothAvailability {
        switch IOBluetoothHostController.default()?.powerState {
        case kBluetoothHCIPowerStateON: return .poweredOn
        case kBluetoothHCIPowerStateOFF: return .poweredOff
        default: return .unavailable
        }
    }

    private static func requestSystemPowerOn() -> Bool {
        guard let framework = dlopen(
            "/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY
        ) else { return false }
        defer { dlclose(framework) }
        guard let symbol = dlsym(framework, "IOBluetoothPreferenceSetControllerPowerState") else {
            return false
        }
        let setPower = unsafeBitCast(symbol, to: (@convention(c) (Int32) -> Void).self)
        setPower(1)
        return true
    }
}
