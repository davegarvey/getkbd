import Foundation
@preconcurrency import IOBluetooth

@MainActor
protocol KeyboardControlling: AnyObject {
    var configuredKeyboard: KeyboardDescriptor? { get set }
    var state: KeyboardConnectionState { get }
    var lastError: String? { get }
    var onStateChange: ((KeyboardConnectionState) -> Void)? { get set }

    func availableKeyboards() -> [KeyboardDescriptor]
    func stop()
    func refreshState()
    func connect() async -> Bool
    func disconnect() async -> Bool
}

private final class ContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false
    private let continuation: CheckedContinuation<Value, Never>

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        lock.lock()
        defer { lock.unlock() }

        guard !hasResumed else { return }
        hasResumed = true
        continuation.resume(returning: value)
    }
}

private final class BluetoothDeviceBox: @unchecked Sendable {
    let device: IOBluetoothDevice

    init(device: IOBluetoothDevice) {
        self.device = device
    }
}

@MainActor
final class IOBluetoothKeyboardController: KeyboardControlling {
    private static let operationTimeoutNanoseconds: UInt64 = 45_000_000_000
    private static let connectionPollNanoseconds: UInt64 = 100_000_000

    private let operationQueue = DispatchQueue(label: "com.getkbd.bluetooth", qos: .userInitiated)
    private var stateValue: KeyboardConnectionState = .unknown
    private var observers: [NSObjectProtocol] = []

    var configuredKeyboard: KeyboardDescriptor? {
        didSet {
            refreshState()
        }
    }

    var state: KeyboardConnectionState { stateValue }
    private(set) var lastError: String?
    var onStateChange: ((KeyboardConnectionState) -> Void)?

    init(configuredKeyboard: KeyboardDescriptor?) {
        self.configuredKeyboard = configuredKeyboard
        installObservers()
        refreshState()
    }

    func availableKeyboards() -> [KeyboardDescriptor] {
        let devices = IOBluetoothDevice.pairedDevices() ?? []

        return devices
            .compactMap { $0 as? IOBluetoothDevice }
            .compactMap { device in
                guard let identifier = device.addressString else { return nil }
                let name = device.name?.isEmpty == false ? device.name! : identifier
                guard Self.looksLikeKeyboard(device: device, name: name) else { return nil }
                return KeyboardDescriptor(identifier: identifier, name: name)
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    func refreshState() {
        guard let device = resolvedDevice() else {
            updateState(.unknown)
            return
        }

        updateState(device.isConnected() ? .connectedLocal : .disconnected)
    }

    func connect() async -> Bool {
        guard let device = resolvedDevice() else {
            fail("No paired keyboard is selected")
            return false
        }

        if device.isConnected() {
            lastError = nil
            updateState(.connectedLocal)
            return true
        }

        lastError = nil
        updateState(.connecting)
        GetKbdLog.event("keyboard.claim.started", configuredKeyboard?.name ?? "")

        let box = BluetoothDeviceBox(device: device)
        let removeResult = await runBluetoothCall { Self.removePairing(box.device) }

        guard let removeResult else {
            fail("Removing the old Bluetooth pairing timed out")
            GetKbdLog.error("keyboard.claim.failed", lastError ?? "Timed out")
            return false
        }

        guard removeResult == kIOReturnSuccess, !device.isPaired() else {
            fail("macOS could not remove the old Bluetooth pairing")
            GetKbdLog.error("keyboard.claim.failed", lastError ?? "Pairing removal failed")
            return false
        }

        GetKbdLog.event("keyboard.pair.started", configuredKeyboard?.name ?? "")
        let pairResult = await runBluetoothCall { Self.pairDevice(box.device) }

        guard let pairResult else {
            fail("Bluetooth pairing timed out")
            GetKbdLog.error("keyboard.claim.failed", lastError ?? "Pairing timed out")
            return false
        }

        guard pairResult == kIOReturnSuccess, device.isPaired() else {
            fail("The keyboard could not be paired with this Mac (IOReturn \(pairResult))")
            GetKbdLog.error("keyboard.claim.failed", lastError ?? "Pairing failed")
            return false
        }

        GetKbdLog.event("keyboard.pair.success")
        let returnCode = await runBluetoothCall { box.device.openConnection() }

        guard let returnCode else {
            fail("Bluetooth connection timed out")
            GetKbdLog.error("keyboard.claim.failed", lastError ?? "Timed out")
            return false
        }

        let connected = await waitForConnection(device, connected: true)
        guard connected else {
            fail("Bluetooth did not report the keyboard as connected (IOReturn \(returnCode))")
            GetKbdLog.error("keyboard.claim.failed", lastError ?? "Unknown failure")
            return false
        }

        lastError = nil
        updateState(.connectedLocal)
        GetKbdLog.event("keyboard.claim.success")
        return true
    }

    func disconnect() async -> Bool {
        guard let device = resolvedDevice() else {
            fail("No paired keyboard is selected")
            return false
        }

        lastError = nil
        updateState(.disconnecting)
        GetKbdLog.event("keyboard.release.started", configuredKeyboard?.name ?? "")

        let box = BluetoothDeviceBox(device: device)
        let returnCode = await runBluetoothCall { Self.removePairing(box.device) }

        guard let returnCode else {
            fail("Removing the Bluetooth pairing timed out")
            GetKbdLog.error("keyboard.release.failed", lastError ?? "Timed out")
            return false
        }

        guard returnCode == kIOReturnSuccess,
              !device.isPaired(),
              !device.isConnected() else {
            fail("macOS did not remove the keyboard pairing")
            GetKbdLog.error("keyboard.release.failed", lastError ?? "Unknown failure")
            return false
        }

        lastError = nil
        updateState(.disconnected)
        GetKbdLog.event("keyboard.release.success")
        return true
    }

    private func resolvedDevice() -> IOBluetoothDevice? {
        guard let identifier = configuredKeyboard?.identifier else { return nil }
        return IOBluetoothDevice(addressString: identifier)
    }

    private func installObservers() {
        let center = NotificationCenter.default
        let connected = Notification.Name("IOBluetoothDeviceConnected")
        let disconnected = Notification.Name("IOBluetoothDeviceDisconnected")

        observers.append(
            center.addObserver(forName: connected, object: nil, queue: .main) { [weak self] notification in
                let address = (notification.object as? IOBluetoothDevice)?.addressString
                MainActor.assumeIsolated {
                    self?.bluetoothDeviceChanged(address: address)
                }
            }
        )
        observers.append(
            center.addObserver(forName: disconnected, object: nil, queue: .main) { [weak self] notification in
                let address = (notification.object as? IOBluetoothDevice)?.addressString
                MainActor.assumeIsolated {
                    self?.bluetoothDeviceChanged(address: address)
                }
            }
        )
    }

    private func bluetoothDeviceChanged(address: String?) {
        guard address == configuredKeyboard?.identifier else {
            return
        }

        refreshState()
    }

    private func updateState(_ newState: KeyboardConnectionState) {
        guard stateValue != newState else { return }
        stateValue = newState
        onStateChange?(newState)
    }

    private func fail(_ message: String) {
        lastError = message
        updateState(.failed)
    }

    // Magic Keyboard handoff requires removing the host bond. A connection close alone leaves
    // macOS free to reconnect the old host, so this undocumented selector is intentionally kept
    // in one replaceable adapter.
    nonisolated private static func removePairing(_ device: IOBluetoothDevice) -> IOReturn {
        if device.isPaired() {
            let removeSelector = NSSelectorFromString("remove")
            guard device.responds(to: removeSelector) else { return kIOReturnError }
            _ = device.perform(removeSelector)
        }

        if device.isConnected() {
            _ = device.closeConnection()
        }

        let deadline = Date().addingTimeInterval(5)
        while (device.isPaired() || device.isConnected()) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        return device.isPaired() || device.isConnected() ? kIOReturnError : kIOReturnSuccess
    }

    nonisolated private static func pairDevice(_ device: IOBluetoothDevice) -> IOReturn {
        guard let pairer = IOBluetoothDevicePair(device: device) else {
            return kIOReturnError
        }

        let delegate = PairingDelegate(deviceName: device.name ?? device.addressString ?? "keyboard")
        pairer.delegate = delegate

        let startResult = pairer.start()
        guard startResult == kIOReturnSuccess else {
            pairer.delegate = nil
            return startResult
        }

        let deadline = Date().addingTimeInterval(20)
        while !delegate.finished && Date() < deadline {
            _ = RunLoop.current.run(
                mode: .default,
                before: min(deadline, Date().addingTimeInterval(0.1))
            )
        }

        guard delegate.finished else {
            pairer.delegate = nil
            pairer.stop()
            return kIOReturnError
        }

        pairer.delegate = nil
        return delegate.result
    }

    private func waitForConnection(_ device: IOBluetoothDevice, connected: Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(10)

        while Date() < deadline {
            if device.isConnected() == connected {
                return true
            }

            try? await Task.sleep(nanoseconds: Self.connectionPollNanoseconds)
        }

        return device.isConnected() == connected
    }

    private func runBluetoothCall(
        _ operation: @escaping @Sendable () -> IOReturn
    ) async -> IOReturn? {
        await withCheckedContinuation { continuation in
            let gate = ContinuationGate(continuation)

            operationQueue.async {
                gate.resume(returning: operation())
            }

            Task.detached {
                try? await Task.sleep(nanoseconds: Self.operationTimeoutNanoseconds)
                gate.resume(returning: nil)
            }
        }
    }

    private static func looksLikeKeyboard(device: IOBluetoothDevice, name: String) -> Bool {
        let major = UInt32(device.deviceClassMajor)
        let minor = UInt32(device.deviceClassMinor)
        let peripheralMajor = UInt32(kBluetoothDeviceClassMajorPeripheral)
        let peripheralType = minor & 0x30

        if major == peripheralMajor,
           peripheralType == UInt32(kBluetoothDeviceClassMinorPeripheral1Keyboard) ||
           peripheralType == UInt32(kBluetoothDeviceClassMinorPeripheral1Combo) {
            return true
        }

        return name.localizedCaseInsensitiveContains("keyboard")
    }
}

private final class PairingDelegate: NSObject, IOBluetoothDevicePairDelegate {
    let deviceName: String
    private(set) var finished = false
    private(set) var result: IOReturn = kIOReturnError

    init(deviceName: String) {
        self.deviceName = deviceName
    }

    func devicePairingStarted(_ sender: Any!) {
        GetKbdLog.event("keyboard.pairing.started", deviceName)
    }

    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        result = error
        finished = true
        GetKbdLog.event("keyboard.pairing.finished", "\(deviceName), IOReturn \(error)")
    }

    func devicePairingUserConfirmationRequest(_ sender: Any!, numericValue: BluetoothNumericValue) {
        GetKbdLog.event("keyboard.pairing.confirmation", "\(deviceName), code \(numericValue)")
        (sender as? IOBluetoothDevicePair)?.replyUserConfirmation(true)
    }

    func devicePairingUserPasskeyNotification(_ sender: Any!, passkey: BluetoothPasskey) {
        GetKbdLog.event("keyboard.pairing.passkey", "\(deviceName), type \(passkey) on the keyboard")
    }

    func devicePairingPINCodeRequest(_ sender: Any!) {
        GetKbdLog.error("keyboard.pairing.pin-required", "Type the Bluetooth PIN on the keyboard")
    }
}
