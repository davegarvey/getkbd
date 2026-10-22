## Why

Swapping which cable each Mac uses to reach the monitor (for example, Thunderbolt on one Mac and USB-C on the other, then reversed) breaks getkbd. macOS gives the monitor a different display identity on each monitor input, and each input exposes its own USB hub chips with different product IDs. getkbd matches the monitor and hubs by those identities, so after the swap it reports the monitor as not connected, never sees its hub group, and holds input numbers learned for the other cable. Settings also lists the monitor twice: the saved identity, marked as not connected, and the new one under the same name.

## What Changes

- Recognise the selected monitor under a new display identity when it is the only online external display with the monitor's name, and remember that identity as another connection of the same monitor.
- Store the USB hub group and the learned input numbers per connection. The hub group is present when a hub from any connection is present.
- When the monitor is connected through a connection with no hub group yet, learn that group from the next switch to the other Mac and back, without opening Settings. Until then, getkbd does not claim the keyboard automatically, does not learn input numbers for it, and the menu asks the user to switch the monitor to the other Mac and back.
- Show the selected monitor once in Settings, whichever connection is online.
- Migrate stored settings to one connection for the saved display and keep writing the earlier keys.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `device-detection`: recognise the selected monitor across display identities and treat hubs from every known connection as the hub group; learn a new connection's hub group from the next switch.
- `monitor-input-switching`: learn and use input numbers per connection.
- `configuration-and-controls`: show one monitor entry, migrate settings, scope "Set Up Again" to the current connection, and add a menu state for a connection that is still being learned.

## Impact

- `Models.swift` (settings schema and migration), `DisplayMonitor`, `HubIdentification`, a new background hub learner, `AppDelegate`, `MenuStatus`, `SettingsView`.
- Settings written by this version stay readable by earlier builds through the legacy keys.
- No new dependencies or permissions.
