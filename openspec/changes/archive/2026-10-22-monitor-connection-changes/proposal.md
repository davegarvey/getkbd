## Why

Swapping which cable each Mac uses to reach the monitor (for example, Thunderbolt on one Mac and USB-C on the other, then reversed) breaks getkbd. macOS gives the monitor a different display identity on each monitor input, so getkbd reports the monitor as not connected, stops switching the main display, and keeps input numbers that now belong to the other Mac. Settings also lists the monitor twice: the saved identity, marked as not connected, and the new one under the same name.

## What Changes

- Recognise the selected monitor under a new display identity when it is the only online external display with the monitor's name, and remember that identity as another connection of the same monitor.
- Keep learned input numbers per connection, and complete a new connection's pair from an earlier connection once one input is read, so that switching the monitor from the menu keeps working after a cable swap.
- Show the selected monitor once in Settings, whichever connection is online.
- Migrate stored inputs to one connection for the saved display and keep writing the earlier key.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `device-detection`: recognise the selected monitor across display identities.
- `monitor-input-switching`: learn and use input numbers per connection, and complete a pair from another connection.
- `configuration-and-controls`: persist connections, show one monitor entry, and migrate settings.

## Impact

- `Models.swift` (settings schema and migration), `DisplayMonitor`, `AppDelegate`, `MenuStatus`, `MenuBarController`, `SettingsView`.
- The USB hub group is unchanged: on the test monitor the KVM hubs are the same devices on either cable.
- Settings written by this version stay readable by earlier builds through the legacy key.
- No new dependencies or permissions.
