## 1. Ownership

- [x] 1.1 Refresh keyboard state in `finishOperation` before clearing `operationInProgress`, and reset the retry count and pending retry on success, and verify with a test that a failed automatic claim is not retried before its scheduled delay
- [x] 1.2 Add `isRetryingClaim` to `OwnershipSnapshot` and publish it after a retry is scheduled, and verify with tests for a pending retry, a retry in flight and an exhausted loop
- [x] 1.3 Add `connectNow()` (cancel the scheduled retry, reset the count, restart or cancel-and-restart the claim, keep the target), and verify with tests and checks for a pending retry, a claim in flight, a release in flight and a failed restart (XCTest cannot run on this machine; the same cases run in the checks harness)

## 2. Keyboard controller

- [x] 2.1 Add `cancelConnect()` to `KeyboardControlling` and a cancellation flag checked before and during pairing in `IOBluetoothKeyboardController`, logging `keyboard.claim.cancelled`

## 3. Menu

- [x] 3.1 Add the Try Now action and the "Keyboard isn’t responding" state to `MenuStatus` and `MenuBarController`, and verify one check per new menu scenario

- [x] 3.2 Show `keyboard.badge.ellipsis` as the menu-bar icon while an operation is in progress or a claim is being retried, and verify the symbol resolves on macOS 26

## 4. Checks, documentation and verification

- [x] 4.1 Add the menu cases to `Checks/GetKbdChecks/main.swift`, and verify the checks pass
- [x] 4.2 Update the README menu and troubleshooting sections
- [x] 4.3 Run `swift build`, `scripts/run-checks.sh` and `openspec validate add-try-now-while-reconnecting --strict`, then install and verify with a sleeping keyboard that Try Now during an attempt starts a new claim within a second and pairs after a power cycle (build, checks and validation passed; on this Mac, with the keyboard switched off, Try Now cancelled the pairing attempt and started a new claim 2 ms later, and after switching it on Try Now paired in 1.5 s; the other Mac is verified after merge from `main`)
