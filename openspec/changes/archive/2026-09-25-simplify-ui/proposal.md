## Why

The menu-bar menu and the settings window expose getkbd's internal sensor model
rather than what the user needs to know. The menu shows six status lines for one
fact, offers Get Keyboard and Release Keyboard in every state, and offers Get
Keyboard on the Mac the monitor is not showing, where it cannot succeed while the
other Mac holds the keyboard. Settings combines setup, a status dashboard, manual
controls and preferences in one large window, uses terms such as "KVM", "input
signal" and "hub", and asks the user to choose a USB hub from a list of vendor
and product IDs that they cannot reliably identify.

## What Changes

- Reduce the menu to one state line, at most one keyboard action, Settings and
  Quit. Offer Release Keyboard only when this Mac has the keyboard, Try Again
  only after a failed operation, and Get Keyboard only when this Mac can
  reasonably take the keyboard: the monitor is showing this Mac or is not
  connected.
- **BREAKING**: Remove Get Keyboard on the Mac the monitor is not showing. The
  documented "release on one Mac, then get on the other" flow is withdrawn.
- **BREAKING**: Remove the global keyboard shortcut, its settings row and the
  Carbon hotkey registration.
- Replace the settings window with a compact macOS settings form: keyboard,
  monitor, monitor switching, a main-display preference and open at login.
  Status notes appear only beside a row with a problem.
- Replace hub selection with a guided step: "Switch your monitor to your other
  Mac, then switch it back." getkbd records every USB hub that leaves and returns
  with the switch as a hub group. Remove the manual hub list; the user retries
  when detection is ambiguous.
- Select the keyboard and monitor automatically when exactly one candidate is
  available.
- Add a "Switch the main display with the monitor" preference, on by default,
  that controls the existing primary-display synchronisation.
- Remove explanatory prose, the manual-controls section, the Open Display
  Settings link and always-visible login-item status from settings.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `configuration-and-controls`: new menu state model and actions, compact
  settings form, guided monitor-switch setup, main-display preference, and
  removal of the global shortcut.
- `device-detection`: hub identification records a group of hubs that change
  with a monitor switch in both directions; the manual hub list is removed.
- `keyboard-handoff`: the automatic signal is the presence of any hub in the
  selected group, and primary-display synchronisation is subject to the new
  preference.

## Impact

- Code: `MenuBarController`, `SettingsView` and `SettingsWindowController` are
  largely rewritten; `AppSettings` gains a hub group and a main-display flag and
  loses the shortcut; `USBHubMonitor` tracks a group of identifiers;
  `DisplayMonitor` respects the preference; `ShortcutController` is deleted;
  `AppDelegate` wiring is simplified.
- Settings migration: an existing single hub selection is read as a group of
  one, and a stored shortcut is ignored. No user action is needed.
- Dependencies: the Carbon framework is no longer linked.
- Documentation: the README's setup, manual switching and controls sections
  change.
- Out of scope: switching the monitor input from getkbd. Tests on a BenQ MA270S
  showed it is feasible through the display cable and will be proposed
  separately.
