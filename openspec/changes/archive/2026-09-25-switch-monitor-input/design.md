## Context

See proposal.md for motivation. Relevant current state:

- `USBHubMonitor.onChange` reports settled hub-group transitions after a
  0.35-second debounce; `AppDelegate` forwards them to `DisplayMonitor` and
  `OwnershipController`.
- `MenuStatus.make` returns a state line and one optional keyboard action;
  `MenuBarController` renders it.
- `AppSettings` has a custom `Codable` implementation that defaults missing keys.
- Prototype results on a BenQ MA270S with an M5 Pro MacBook Pro:
  - This Mac reported input 19 and the other Mac input 21. Neither is an MCCS
    standard value, so values cannot be assumed.
  - The monitor did not answer for 2–5 seconds during an input change, and
    occasionally dropped a single reading while idle.
  - Setting input 21 from the active Mac and input 19 from the inactive Mac both
    worked. The existing hub handoff followed in each case.

## Goals / Non-Goals

**Goals:**

- Keep all DDC/CI access behind one small adapter so the undocumented functions
  are isolated and replaceable.
- Keep learning and menu logic pure and testable without hardware.
- Never let a monitor-control failure affect keyboard ownership or the primary
  display.

**Non-Goals:**

- Intel Macs, which use a different I2C interface. The actions are hidden there.
- Polling the monitor to detect input changes. The hub group remains the only
  ownership signal.
- Any settings UI for input numbers.

## Decisions

### A `MonitorInputControl` protocol with an IOAVService adapter

```swift
protocol MonitorInputControl {
    func readInput() async -> Int?
    func setInput(_ value: Int) async -> Bool
}
```

`IOAVMonitorInputControl` declares the three IOKit functions with
`@_silgen_name`, as the prototype did, and runs I2C calls on a serial background
queue. A read writes the VCP 0x60 request, waits 50 ms, reads 12 bytes, and
validates the reply header, VCP code and result byte. It retries up to five
times with 50 ms between attempts. A write sends the set-VCP packet twice, which
is how existing tools handle dropped writes.

*Alternative considered*: shelling out to a bundled `m1ddc`. Rejected: it adds a
binary dependency for about 100 lines of code.

### Matching the control channel to the selected display

The adapter walks the IORegistry and pairs each external `DCPAVServiceProxy`
with the `IOMobileFramebufferShim` in the same `dispextN` subtree. It then
compares that framebuffer's `DisplayAttributes.ProductAttributes`
(`LegacyManufacturerID`, `ProductID`, `SerialNumber`) with
`CGDisplayVendorNumber`, `CGDisplayModelNumber` and `CGDisplaySerialNumber` for
the selected display. On the test machine these matched: 2513, 32990 and
16843009. If exactly one external proxy exists and matching fails, it is used,
because there is no ambiguity. Otherwise the control is unavailable.

The adapter resolves the channel on each call rather than caching it, because
the registry entry is recreated when displays reconnect.

### Accepting a reading

`MonitorInputLearner` asks for up to eight readings, one second apart, and
accepts a value once two consecutive readings agree. A read is triggered:

- at launch;
- after each settled hub-group transition;
- when the hub group changes in settings (after setup).

A read in progress is cancelled when a new transition arrives, so a stale
reading from before a switch is never recorded against the new state.

*Alternative considered*: reading during setup identification. Rejected:
learning after every transition covers setup and existing users with the same
code, and keeps the numbers current if a cable is moved to another port.

### Storage

`AppSettings` gains `monitorInputs: LearnedMonitorInputs?`, containing
`displayIdentifier`, `thisMac: Int?` and `otherMac: Int?`. It decodes as `nil`
when absent. The inputs are cleared whenever `selectedDisplay` changes. The
learner writes through the same `apply(_:)` path as other settings changes, but
input updates alone do not call `ownershipController.updateSignals`, because
that would reset a manual keyboard target.

### Menu

`MenuStatus` gains `monitorAction: MonitorAction?`
(`.switchToOtherMac` or `.switchToThisMac`), computed from the spec's
scenarios. `MenuStatus.make` takes a `monitorControlAvailable` flag. Availability
is the result of the most recent read attempt, so opening the menu never waits
on I2C. The monitor item goes directly below the keyboard action, in the same
section.

### Switching

On selection, `AppDelegate` calls `setInput` off the main actor and starts a
15-second watchdog. A hub-group transition cancels the watchdog. On timeout, or
if the write fails, it logs `monitor.switch.failed`. No state is shown in the
menu, because the monitor visibly either switches or does not.

## Risks / Trade-offs

- [Undocumented functions could change in a future macOS] → They are isolated
  in one adapter, and failure only hides two menu items. They have been stable
  across Apple Silicon releases and are used by BetterDisplay and Lunar.
- [Some monitors ignore commands on inactive inputs] → Each direction depends
  only on its own learned input. If a switch has no effect, the watchdog logs it.
  The user still has the monitor's buttons.
- [DDC traffic could clash with Display Pilot 2] → getkbd reads only after
  transitions and writes only on user action, so traffic is a few messages per
  switch.
- [A reading taken mid-switch could be wrong] → Two consecutive agreeing
  readings are required, reads are cancelled by newer transitions, and a reading
  that equals the other Mac's input is discarded.
- [The other Mac's input is unknown until the first switch away] → This is
  acceptable. The action appears after the first manual switch, and the monitor
  buttons work meanwhile.

## Migration Plan

No migration is needed. Existing settings decode with no learned inputs, and the
actions appear once the inputs have been learned. Earlier builds ignore the new
key.
