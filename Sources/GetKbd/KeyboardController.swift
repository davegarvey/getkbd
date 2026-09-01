import AppKit
import Foundation
@preconcurrency import IOBluetooth

@MainActor
protocol KeyboardControlling: AnyObject {
    var configuredKeyboard: KeyboardDescriptor? { get set }
    var state: KeyboardConnectionState { get }
    var lastError: String? { get }
    var onStateChange: ((KeyboardConnectionState) -> Void)? { get set }

    func availableKeyboards() async -> [KeyboardDescriptor]
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
    nonisolated private static let pairingTimeout: TimeInterval = 45
    private static let handoffSettleDelayNanoseconds: UInt64 = 1_000_000_000
    private static let connectionPollNanoseconds: UInt64 = 100_000_000

    private let operationQueue = DispatchQueue(label: "com.getkbd.bluetooth", qos: .userInitiated)
    private let deviceLookupQueue = DispatchQueue(
        label: "com.getkbd.bluetooth.lookup",
        qos: .utility,
        attributes: .concurrent
    )
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
    }

    func availableKeyboards() async -> [KeyboardDescriptor] {
        await withCheckedContinuation { continuation in
            deviceLookupQueue.async {
                continuation.resume(returning: Self.discoverKeyboards())
            }
        }
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    func refreshState() {
        guard let identifier = configuredKeyboard?.identifier,
              let device = Self.device(identifier: identifier) else {
            updateState(.unknown)
            return
        }

        updateState(device.device.isConnected() ? .connectedLocal : .disconnected)
    }

    func connect() async -> Bool {
        guard let box = await resolvedDevice() else {
            fail("No paired keyboard is selected")
            return false
        }
        let device = box.device

        if await runBluetoothCheck({ device.isPaired() && device.isConnected() }) {
            lastError = nil
            updateState(.connectedLocal)
            return true
        }

        lastError = nil
        updateState(.connecting)
        GetKbdLog.event("keyboard.claim.started", configuredKeyboard?.name ?? "")

        let removeResult = await runBluetoothCall { Self.removePairing(box.device) }

        guard let removeResult else {
            fail("Removing the old Bluetooth pairing timed out")
            GetKbdLog.error("keyboard.claim.failed", lastError ?? "Timed out")
            return false
        }

        let isPairedAfterRemoval = await runBluetoothCheck { device.isPaired() }
        let isConnectedAfterRemoval = await runBluetoothCheck { device.isConnected() }
        guard removeResult == kIOReturnSuccess, !isPairedAfterRemoval, !isConnectedAfterRemoval else {
            fail("macOS could not remove the old Bluetooth pairing")
            GetKbdLog.error("keyboard.claim.failed", lastError ?? "Pairing removal failed")
            return false
        }

        // Magic Keyboards need a short interval after their old bond is removed before they
        // reliably accept a new pairing attempt.
        try? await Task.sleep(nanoseconds: Self.handoffSettleDelayNanoseconds)

        GetKbdLog.event("keyboard.pair.started", configuredKeyboard?.name ?? "")
        let pairResult = await runBluetoothCall { Self.pairDevice(box.device) }

        guard let pairResult else {
            fail("Bluetooth pairing timed out")
            GetKbdLog.error("keyboard.claim.failed", lastError ?? "Pairing timed out")
            return false
        }

        let isPairedAfterPairing = await runBluetoothCheck { device.isPaired() }
        guard pairResult == kIOReturnSuccess, isPairedAfterPairing else {
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

        guard await runBluetoothCheck({ device.isPaired() }) else {
            fail("Bluetooth connected, but the keyboard pairing did not finish")
            GetKbdLog.error("keyboard.claim.failed", lastError ?? "Pairing did not finish")
            return false
        }

        lastError = nil
        updateState(.connectedLocal)
        GetKbdLog.event("keyboard.claim.success")
        return true
    }

    func disconnect() async -> Bool {
        guard let box = await resolvedDevice() else {
            fail("No paired keyboard is selected")
            return false
        }
        let device = box.device

        lastError = nil
        updateState(.disconnecting)
        GetKbdLog.event("keyboard.release.started", configuredKeyboard?.name ?? "")

        let returnCode = await runBluetoothCall { Self.removePairing(box.device) }

        guard let returnCode else {
            fail("Removing the Bluetooth pairing timed out")
            GetKbdLog.error("keyboard.release.failed", lastError ?? "Timed out")
            return false
        }

        let isPairedAfterRemoval = await runBluetoothCheck { device.isPaired() }
        let isConnectedAfterRemoval = await runBluetoothCheck { device.isConnected() }
        guard returnCode == kIOReturnSuccess, !isPairedAfterRemoval, !isConnectedAfterRemoval else {
            fail("macOS did not remove the keyboard pairing")
            GetKbdLog.error("keyboard.release.failed", lastError ?? "Unknown failure")
            return false
        }

        lastError = nil
        updateState(.disconnected)
        GetKbdLog.event("keyboard.release.success")
        return true
    }

    private func resolvedDevice() async -> BluetoothDeviceBox? {
        guard let identifier = configuredKeyboard?.identifier else { return nil }
        return Self.device(identifier: identifier)
    }

    nonisolated private static func device(identifier: String) -> BluetoothDeviceBox? {
        guard let device = IOBluetoothDevice(addressString: identifier) else { return nil }
        return BluetoothDeviceBox(device: device)
    }

    nonisolated private static func discoverKeyboards() -> [KeyboardDescriptor] {
        (IOBluetoothDevice.pairedDevices() ?? [])
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
        guard let address,
              let configuredIdentifier = configuredKeyboard?.identifier,
              normalizedBluetoothIdentifier(address) == normalizedBluetoothIdentifier(configuredIdentifier) else {
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

            // Do not explicitly close a Magic Keyboard after removing its bond. The Bluetooth
            // stack may leave the accessory unavailable for the next host if the connection is
            // closed as a separate operation immediately afterward.
            let deadline = Date().addingTimeInterval(5)
            while (device.isPaired() || device.isConnected()) && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }

            if device.isConnected() {
                _ = device.closeConnection()
                let disconnectDeadline = Date().addingTimeInterval(5)
                while device.isConnected() && Date() < disconnectDeadline {
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }

            return device.isPaired() || device.isConnected() ? kIOReturnError : kIOReturnSuccess
        }

        if device.isConnected() {
            let returnCode = device.closeConnection()
            guard returnCode == kIOReturnSuccess else { return returnCode }

            let deadline = Date().addingTimeInterval(5)
            while device.isConnected() && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            return device.isConnected() ? kIOReturnError : kIOReturnSuccess
        }

        return kIOReturnSuccess
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

        let deadline = Date().addingTimeInterval(Self.pairingTimeout)
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
            if await runBluetoothCheck({ device.isConnected() }) == connected {
                return true
            }

            try? await Task.sleep(nanoseconds: Self.connectionPollNanoseconds)
        }

        return await runBluetoothCheck({ device.isConnected() }) == connected
    }

    private func runBluetoothCheck(
        _ operation: @escaping @Sendable () -> Bool
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            operationQueue.async {
                continuation.resume(returning: operation())
            }
        }
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

    nonisolated private static func looksLikeKeyboard(device: IOBluetoothDevice, name: String) -> Bool {
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
        CFRunLoopStop(CFRunLoopGetCurrent())
        GetKbdLog.event("keyboard.pairing.finished", "\(deviceName), IOReturn \(error)")
    }

    func devicePairingUserConfirmationRequest(_ sender: Any!, numericValue: BluetoothNumericValue) {
        GetKbdLog.event("keyboard.pairing.confirmation", "\(deviceName), code \(numericValue)")
        (sender as? IOBluetoothDevicePair)?.replyUserConfirmation(true)
    }

    func devicePairingUserPasskeyNotification(_ sender: Any!, passkey: BluetoothPasskey) {
        let formattedPasskey = String(format: "%06u", passkey)
        GetKbdLog.event("keyboard.pairing.passkey", "\(deviceName), type \(formattedPasskey) on the keyboard")
        Self.showPairingPrompt(
            title: "Type the passkey on the keyboard",
            message: "Type \(formattedPasskey) on \(deviceName), then press Return."
        )
    }

    func devicePairingPINCodeRequest(_ sender: Any!) {
        GetKbdLog.error("keyboard.pairing.pin-required", "Type the Bluetooth PIN on the keyboard")
        Self.showPairingPrompt(
            title: "Bluetooth PIN required",
            message: "Type the Bluetooth PIN on \(deviceName), then press Return."
        )
    }

    private static func showPairingPrompt(title: String, message: String) {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "Continue")
            alert.runModal()
        }
    }
}
