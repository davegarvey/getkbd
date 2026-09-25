## Context

See proposal.md for motivation. The relevant current state:

- `MenuBarController` builds the menu directly from `OwnershipSnapshot` and
  `AppSettings`, adding a label for each sensor and both keyboard actions in
  every state.
- `SettingsView` is a single 760×560 scrolling view containing a readiness card,
  three group boxes, manual controls and a shortcut recorder. Hub identification
  in `SettingsViewModel.usbHubListChanged` accepts exactly one changed hub and
  otherwise falls back to a manual list.
- `USBHubMonitor` tracks one configured identifier, receives IOKit arrival and
  termination notifications, and debounces aggregate presence for 0.35 seconds.
- `DisplayMonitor.synchronizePrimaryDisplay` always runs when a hub is configured.
- `ShortcutController` registers a Carbon hotkey. Carbon is otherwise used only
  for virtual key codes in `ShortcutConfiguration` and the shortcut recorder.
- `swift test` requires XCTest, which is unavailable when only Command Line Tools
  are installed. `scripts/run-checks.sh` compiles the app sources with a small
  check harness and runs without XCTest.

## Goals / Non-Goals

**Goals:**

- Make menu content a pure function of settings and ownership state so every
  menu state in the spec can be tested without AppKit.
- Make hub-group identification a pure state machine driven by hub-set
  snapshots so it can be tested without USB hardware.
- Keep ownership, Bluetooth and primary-display logic unchanged apart from the
  hub-group signal and the preference gate.

**Non-Goals:**

- Switching the monitor input over DDC/CI. This will be a separate change.
- Changing the menu-bar icon set.
- Changing keyboard claim or release mechanics, retries or sleep handling.

## Decisions

### Menu content is computed by a pure `MenuStatus` value

`MenuStatus.make(settings:snapshot:failedTarget:)` returns a state line and an
optional action (`release`, `get`, `retry`, `finishSetup` or none), following the
precedence in the spec: setup incomplete, busy, failed, connected, display
offline, hub present, otherwise "showing your other Mac". `MenuBarController`
only renders it.

*Alternative considered*: keep branching inside `makeMenu()`. Rejected because
the menu's behaviour is now its main contract and should be unit-tested.

`OwnershipController` already exposes `desiredState`; the retry target is taken
from it as today, so no new ownership state is needed.

### The hub selection becomes a group of descriptors

`AppSettings.selectedUSBHub: USBHubDescriptor?` becomes
`selectedUSBHubs: [USBHubDescriptor]`. The decoder reads the new key, or wraps a
legacy `selectedUSBHub` value in an array. The encoder writes the new key and
also writes the first hub under the legacy key, so an earlier build can still
start with a working selection.
`needsOnboarding` checks for an empty group. The `shortcut` key is no longer
decoded or encoded; JSON decoding ignores it in old data.

`USBHubMonitor.configuredHubIdentifier` becomes `configuredHubIdentifiers:
Set<String>`, and raw presence becomes "any connected hub's identifier is in the
set". Because the existing debounce acts on aggregate presence, staggered
arrivals within a group already produce a single transition.

*Alternative considered*: store only one representative hub. Rejected because a
slow or re-enumerated hub would then decide presence alone.

### Identification is a phase-based state machine

`HubIdentification` holds the baseline set of hub identifiers and advances on
settled snapshots of the current set:

1. **Waiting for the first switch**: the first settled snapshot that differs from
   the baseline records `firstChange`, the symmetric difference.
2. **Waiting for the switch back**: each settled snapshot computes which hubs in
   `firstChange` are back in their baseline state. When at least one has
   returned and the set has been stable for the settle interval, the result is
   the returned hubs, described using the baseline or current descriptors.
3. **Failed**: a two-minute timeout, cancellation or a second-phase settle with no
   returned hub.

A snapshot counts as settled after 2 seconds without further hub-list changes.
The monitor stops responding for several seconds during an input switch, and
hubs can enumerate in stages, so the 0.35-second presence debounce is too short
for this purpose. The view model owns the timer; the state machine receives
timestamps so tests can drive it.

Hubs that change only once, such as a device plugged in during setup, never
appear in the returned set.

*Alternative considered*: keep the current one-shot comparison and accept all
changed hubs. Rejected because it cannot exclude unrelated devices without the
return trip.

### Settings uses a grouped SwiftUI `Form`

The window becomes a fixed-width (about 480pt) `Form` with `.formStyle(.grouped)`:

- **Devices**: Keyboard picker, Monitor picker, Monitor switching row.
- **Behaviour**: main-display toggle with a one-line description, Open at login.

While setup is incomplete, the next step renders as a prominent section at the
top: a keyboard or monitor prompt, or the monitor-switch instructions with a
progress label for the current identification phase. After setup completes, the
section shows a brief confirmation until the window closes. Row notes (such as
"Not connected") use secondary or orange text beside the value.

The view model auto-selects a keyboard or display when its selection is empty
and the loaded candidate list has exactly one entry.

*Alternative considered*: a separate multi-page setup assistant. Rejected as more
code and a second window, for a flow each user performs twice.

### The main-display preference gates `DisplayMonitor`

`AppSettings` gains `switchMainDisplay: Bool`, decoded with a default of `true`.
`DisplayMonitor` gains `primarySyncEnabled`; `synchronizePrimaryDisplay` returns
early when it is false. Enabling it calls `scheduleEvaluation(forcePrimarySync:
true)`. Disabling it performs no display change.

### Shortcut removal

Delete `ShortcutController.swift`, `ShortcutConfiguration`, the recorder in the
view model and the menu key equivalent. Remove `import Carbon` and the Carbon
framework from `Package.swift`, `scripts/run-checks.sh` and the tech stack in
`openspec/config.yaml`.

## Risks / Trade-offs

- [Users of the release-then-get flow lose it] → The monitor controls remain the
  switch; a later change adds a DDC switch button. The README is updated.
- [Identification requires switching back; a user who only switches away sees a
  timeout] → The progress label says which part of the switch is awaited, and the
  timeout message says to switch back.
- [A monitor whose hubs never reappear with the same identifiers] → Identifiers
  already fall back to vendor, product, name and manufacturer when no serial is
  available; if identification still fails, the user sees a retry message with
  no workaround. This is accepted in place of a list the user cannot interpret.
- [Hiding raw Bluetooth errors makes support harder] → Errors are logged at
  `error` level, and event logging is persisted by the separate logging change.
- [XCTest is unavailable on some development machines] → Pure logic (menu status,
  identification, settings migration) is also exercised in the
  `scripts/run-checks.sh` harness, which does not need XCTest.

## Migration Plan

Settings migrate on first launch of the new version without user action. Rolling
back to an earlier build keeps a working selection through the legacy key, using
the first hub in the group, and restores the default shortcut.
