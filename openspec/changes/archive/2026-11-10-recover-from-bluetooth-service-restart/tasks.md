## 1. Implementation

- [x] 1.1 Add `BluetoothServiceIdentity` lookup of `bluetoothd`'s PID and start time with `sysctl`
- [x] 1.2 Add `BluetoothRecoveryPolicy`: baseline identity, rate limit, unanswered-claim count, sleep and in-progress deferral, once-per-detection skip logging
- [x] 1.3 Add a relauncher that waits for the current process to exit and reopens the app bundle, recording the relaunch time
- [x] 1.4 Return `kIOReturnTimeout` when pairing ends at getkbd's deadline without a delegate result, and expose it to the ownership layer
- [x] 1.5 Add a claim gate and an operation-finished callback to `OwnershipController`
- [x] 1.6 Wire the monitor in `AppDelegate`: 30 s timer, wake and sleep, claim gate, release-then-relaunch, unanswered claims
- [x] 1.7 Add the new source file to `scripts/run-checks.sh`

## 2. Verification

- [x] 2.1 Add checks for the policy: restart detection, deferral during operations and sleep, unanswered-claim fallback, manual claims ignored, rate limit, skip logged once
- [x] 2.2 Add an ownership check that a refused claim gate starts no operation
- [x] 2.3 Build with `xcrun swift build` and run `scripts/run-checks.sh`
- [x] 2.4 Install on this Mac and confirm the identity is logged at start and no relaunch occurs while idle
- [ ] 2.5 Optional, needs the user: `sudo pkill bluetoothd` on one Mac, then confirm a logged detection, a relaunch and a successful claim
