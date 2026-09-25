## 1. Monitor input control

- [x] 1.1 Add the `MonitorInputControl` protocol and `IOAVMonitorInputControl` adapter (read with reply validation and retries, write sent twice, off the main actor), and verify with a debug build that `readInput()` returns 19 on the BenQ MA270S
- [x] 1.2 Match the control channel to the selected display by vendor, model and serial numbers, falling back to a single external channel, and verify it resolves the BenQ and returns `nil` for an unknown display identifier
- [x] 1.3 Add a reply-parsing function covering valid, wrong-VCP, unsupported and short replies, and verify with checks-harness cases using the reply bytes captured in the prototype

## 2. Learning inputs

- [x] 2.1 Add `LearnedMonitorInputs` to `AppSettings` (decoded as `nil` when absent, cleared when the selected display changes), and verify decoding of old settings and the reset in settings tests
- [x] 2.2 Implement `MonitorInputLearner` (two agreeing readings from up to eight, cancellation on a newer transition, discarding conflicts), and verify with a fake `MonitorInputControl` in tests for present, absent, disagreeing, conflicting and cancelled readings
- [x] 2.3 Wire the learner to launch, settled hub-group transitions and hub-group changes in `AppDelegate`, without resetting manual keyboard targets, and verify in the running app that both inputs are learned after one switch away and back

## 3. Menu and switching

- [x] 3.1 Add `monitorAction` to `MenuStatus` with the spec's conditions, and verify one test per new menu scenario
- [x] 3.2 Render the monitor action in `MenuBarController` below the keyboard action, send `setInput` off the main actor with a 15-second watchdog logging `monitor.switch.failed`, and verify both directions in the running app using the persisted log

## 4. Checks and documentation

- [x] 4.1 Add the learner, reply-parsing and menu cases to `Checks/GetKbdChecks/main.swift` and `scripts/run-checks.sh`, and verify the checks pass
- [x] 4.2 Update the README (menu section, requirements and the statement about what getkbd accesses), and verify the text matches the menu in the running app
- [x] 4.3 Run `swift build`, `scripts/run-checks.sh` and `openspec validate switch-monitor-input --strict`, then install on both Macs and verify switching in both directions from each Mac (build, checks and validation passed; this Mac verified in both directions; the other Mac is verified after merge from `main`)
