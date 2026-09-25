## 1. Settings model

- [x] 1.1 Replace `selectedUSBHub` with `selectedUSBHubs` in `AppSettings`, decode the legacy key into a group of one, encode both keys, and verify with a round-trip and legacy-decode test
- [x] 1.2 Add `switchMainDisplay` (default `true`, decoded with a default when missing) and verify old settings decode with it enabled
- [x] 1.3 Remove `ShortcutConfiguration` and the `shortcut` field, and verify settings containing a `shortcut` key still decode without requiring setup

## 2. Shortcut removal

- [x] 2.1 Delete `ShortcutController.swift` and its wiring in `AppDelegate`, and verify `swift build` succeeds
- [x] 2.2 Remove `import Carbon` and the Carbon framework from `Package.swift` and `scripts/run-checks.sh`, update the tech stack in `openspec/config.yaml`, and verify the build and checks pass

## 3. Hub group detection

- [x] 3.1 Change `USBHubMonitor` to track `configuredHubIdentifiers: Set<String>` with any-present semantics, update `AppDelegate` wiring, and verify existing ownership tests still pass
- [x] 3.2 Implement the `HubIdentification` state machine (baseline, first switch, switch back, failed, two-minute timeout, 2-second settle) and verify tests for leave-and-return, arrive-and-leave, an unrelated one-way change, and no return
- [x] 3.3 Remove the manual hub list and single-hub identification from `SettingsViewModel`, drive `HubIdentification` from hub-list changes, and verify a failed identification keeps the previous group

## 4. Main-display preference

- [x] 4.1 Add `primarySyncEnabled` to `DisplayMonitor`, skip synchronisation when disabled, force an evaluation when enabled, and verify with `DisplayPrimaryTests` cases for disabled, re-enabled, and wake while disabled
- [ ] 4.2 Apply `switchMainDisplay` from settings at launch and on change in `AppDelegate`, and verify by toggling it in the running app

## 5. Menu

- [x] 5.1 Implement `MenuStatus.make` with the precedence in design.md and verify one test per menu scenario in the spec
- [x] 5.2 Rewrite `MenuBarController.makeMenu()` to render `MenuStatus` (state line, optional action, Settings or Finish Setup, Quit), remove sensor labels, the shortcut label and key equivalents, and verify the menu in the running app for connected, other-Mac, and setup-incomplete states

## 6. Settings window

- [x] 6.1 Replace `SettingsView` with a grouped `Form` (Devices: keyboard, monitor, monitor switching; Behaviour: main display, open at login) at about 480pt wide, and resize `SettingsWindowController` to fit; verify visually in the running app
- [x] 6.2 Add the setup section shown while setup is incomplete, with the identification phase label, the completion confirmation, and the reminder to set up the other Mac; verify by clearing settings and completing setup on the BenQ MA270S
- [x] 6.3 Auto-select the keyboard and monitor when exactly one candidate exists, and verify with a view-model test
- [ ] 6.4 Show row notes only for an offline monitor or a login item requiring approval (no keyboard note, because a released keyboard is unpaired on that Mac), and verify each by simulating the condition

## 7. Checks and documentation

- [x] 7.1 Add `MenuStatus`, `HubIdentification`, and settings-migration cases to `Checks/GetKbdChecks/main.swift` and verify `scripts/run-checks.sh` passes without XCTest
- [x] 7.2 Update the README setup, use, manual switching, controls and troubleshooting sections to remove the shortcut, the hub list and the release-then-get flow, and verify no remaining references with `git grep -i -E 'shortcut|identify input signal|Select the USB hub'`
- [ ] 7.3 Run `swift build`, `scripts/run-checks.sh`, `swift test` where XCTest is available, and `openspec validate simplify-ui --strict`, then install the app on both Macs and verify a full monitor switch in each direction using the persisted log
