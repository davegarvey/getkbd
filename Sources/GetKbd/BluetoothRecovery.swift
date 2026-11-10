import AppKit
import Darwin
import Foundation

/// Identifies one run of macOS's Bluetooth daemon. The start time guards against PID reuse.
struct BluetoothServiceIdentity: Equatable, Sendable, CustomStringConvertible {
    let pid: Int32
    let startSeconds: Int
    let startMicroseconds: Int32

    var description: String { "pid=\(pid) started=\(startSeconds)" }

    /// Finds `bluetoothd` in the process table. Listing processes needs no privileges.
    static func current() -> BluetoothServiceIdentity? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }

        // Leave room for processes started between the two calls.
        let capacity = size / MemoryLayout<kinfo_proc>.stride + 32
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        size = capacity * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &processes, &size, nil, 0) == 0 else { return nil }

        let count = size / MemoryLayout<kinfo_proc>.stride
        return processes.prefix(count)
            .filter { processName($0) == "bluetoothd" }
            .min { $0.kp_proc.p_pid < $1.kp_proc.p_pid }
            .map {
                BluetoothServiceIdentity(
                    pid: $0.kp_proc.p_pid,
                    startSeconds: Int($0.kp_proc.p_starttime.tv_sec),
                    startMicroseconds: Int32($0.kp_proc.p_starttime.tv_usec)
                )
            }
    }

    private static func processName(_ process: kinfo_proc) -> String {
        var name = process.kp_proc.p_comm
        return withUnsafeBytes(of: &name) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// Decides when getkbd must relaunch to get a fresh Bluetooth session.
///
/// After `bluetoothd` restarts, a long-running process can be left with a session in which
/// the daemon has no address for the keyboard, so every claim pages 00:00:00:00:00:00. No
/// in-process lookup reveals or repairs this; a new process does.
struct BluetoothRecoveryPolicy: Sendable {
    enum Reason: Equatable, Sendable, CustomStringConvertible {
        case serviceRestarted
        case unansweredClaims

        var description: String {
            switch self {
            case .serviceRestarted: "bluetooth service restarted"
            case .unansweredClaims: "claims got no answer from Bluetooth"
            }
        }
    }

    enum Decision: Equatable, Sendable {
        case none
        /// A relaunch is due but must wait for an operation or for wake.
        case deferred
        case relaunch(Reason)
        /// A relaunch is due but the rate limit applies. `log` is true once per detection.
        case skipped(Reason, log: Bool)
    }

    static let minimumRelaunchInterval: TimeInterval = 600
    static let unansweredClaimLimit = 2

    private(set) var baseline: BluetoothServiceIdentity?
    private(set) var restartedIdentity: BluetoothServiceIdentity?
    private(set) var unansweredClaims = 0
    var lastRelaunch: Date?
    private var loggedSkip: Reason?

    init(lastRelaunch: Date? = nil) {
        self.lastRelaunch = lastRelaunch
    }

    var pendingReason: Reason? {
        if restartedIdentity != nil { return .serviceRestarted }
        if unansweredClaims >= Self.unansweredClaimLimit { return .unansweredClaims }
        return nil
    }

    /// Records the daemon's identity. Returns the new identity when a restart is first seen.
    /// A missing daemon is not a restart: its replacement will have a new identity.
    mutating func observe(_ identity: BluetoothServiceIdentity?) -> BluetoothServiceIdentity? {
        guard let identity else { return nil }
        guard let baseline else {
            self.baseline = identity
            return nil
        }
        guard identity != baseline, identity != restartedIdentity else { return nil }
        restartedIdentity = identity
        loggedSkip = nil
        return identity
    }

    /// Counts automatic claims that ended at getkbd's own timeout without any Bluetooth result.
    /// Manual claims are ignored, so a person answering a pairing prompt is never interrupted.
    mutating func claimFinished(succeeded: Bool, automatic: Bool, unanswered: Bool) {
        if succeeded {
            unansweredClaims = 0
        } else if automatic {
            unansweredClaims = unanswered ? unansweredClaims + 1 : 0
        }
    }

    mutating func decide(now: Date, operationInProgress: Bool, sleeping: Bool) -> Decision {
        guard let reason = pendingReason else { return .none }
        guard !operationInProgress, !sleeping else { return .deferred }

        if let lastRelaunch,
           now >= lastRelaunch,
           now.timeIntervalSince(lastRelaunch) < Self.minimumRelaunchInterval {
            let log = loggedSkip != reason
            loggedSkip = reason
            return .skipped(reason, log: log)
        }
        return .relaunch(reason)
    }

    /// Accepts the current state as normal, for when a relaunch is not possible.
    mutating func acceptCurrentState() {
        if let restartedIdentity {
            baseline = restartedIdentity
        }
        restartedIdentity = nil
        unansweredClaims = 0
        loggedSkip = nil
    }
}

@MainActor
protocol ApplicationRelaunching {
    /// Starts a new instance once this process has exited and terminates this one.
    /// Returns false when getkbd cannot relaunch, for example outside an app bundle.
    func relaunch() -> Bool
}

struct BundleRelauncher: ApplicationRelaunching {
    func relaunch() -> Bool {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else { return false }

        // Waiting for this process to exit keeps two instances from acting on the keyboard.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; exec /usr/bin/open \"$2\"",
            "getkbd-relaunch",
            String(getpid()),
            bundleURL.path
        ]
        do {
            try process.run()
        } catch {
            GetKbdLog.error("bluetooth.relaunch.failed", error.localizedDescription)
            return false
        }
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
        return true
    }
}

/// Watches for a `bluetoothd` restart and unanswered claims, and relaunches getkbd when due.
@MainActor
final class BluetoothRecoveryMonitor {
    static let lastRelaunchKey = "lastBluetoothRelaunchAt"
    private static let checkIntervalSeconds: TimeInterval = 30

    var isOperationInProgress: () -> Bool = { false }

    private var policy: BluetoothRecoveryPolicy
    private let identity: () -> BluetoothServiceIdentity?
    private let relauncher: ApplicationRelaunching
    private let defaults: UserDefaults
    private let now: () -> Date
    private var timer: Timer?
    private var sleeping = false
    private(set) var isRelaunching = false

    init(
        identity: @escaping () -> BluetoothServiceIdentity? = BluetoothServiceIdentity.current,
        relauncher: ApplicationRelaunching? = nil,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.identity = identity
        self.relauncher = relauncher ?? BundleRelauncher()
        self.defaults = defaults
        self.now = now
        let stored = defaults.double(forKey: Self.lastRelaunchKey)
        policy = BluetoothRecoveryPolicy(lastRelaunch: stored > 0 ? Date(timeIntervalSince1970: stored) : nil)
    }

    func start() {
        _ = policy.observe(identity())
        GetKbdLog.event("bluetooth.service.identity", policy.baseline?.description ?? "not found")
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluate()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func willSleep() {
        sleeping = true
    }

    func didWake() {
        sleeping = false
        evaluate()
    }

    /// Asked before a claim starts. Returns false when getkbd is relaunching instead, in which
    /// case the new instance claims according to the current signals.
    func allowClaim() -> Bool {
        guard !isRelaunching else { return false }
        evaluate()
        return !isRelaunching
    }

    func operationFinished(target: DesiredKeyboardState, succeeded: Bool, automatic: Bool, unanswered: Bool) {
        if target == .connected {
            policy.claimFinished(succeeded: succeeded, automatic: automatic, unanswered: unanswered)
        }
        evaluate()
    }

    func evaluate() {
        guard !isRelaunching else { return }
        if let restarted = policy.observe(identity()) {
            GetKbdLog.event(
                "bluetooth.service.restarted",
                "was \(policy.baseline?.description ?? "unknown"), now \(restarted)"
            )
        }

        switch policy.decide(now: now(), operationInProgress: isOperationInProgress(), sleeping: sleeping) {
        case .none, .deferred, .skipped(_, log: false):
            return
        case .skipped(let reason, log: true):
            GetKbdLog.event("bluetooth.relaunch.skipped", "\(reason); relaunched less than 10 minutes ago")
        case .relaunch(let reason):
            relaunch(reason)
        }
    }

    private func relaunch(_ reason: BluetoothRecoveryPolicy.Reason) {
        let time = now()
        GetKbdLog.event("bluetooth.relaunch.started", reason.description)
        guard relauncher.relaunch() else {
            GetKbdLog.event("bluetooth.relaunch.unavailable", "\(reason); getkbd is not running from an app bundle")
            policy.acceptCurrentState()
            return
        }
        policy.lastRelaunch = time
        defaults.set(time.timeIntervalSince1970, forKey: Self.lastRelaunchKey)
        isRelaunching = true
        stop()
    }
}
