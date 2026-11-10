## Why

On 2026-11-10 the keyboard was left connected to neither Mac. This Mac released it correctly when the monitor switched away, but every claim from the other Mac failed for six minutes. By the time the monitor came back, the keyboard no longer answered either Mac, and it needed a power cycle.

The other Mac's logs give the cause. macOS's Bluetooth service, `bluetoothd`, had restarted overnight without a reboot. getkbd kept running through the restart, but `bluetoothd` no longer had an address for the device getkbd asked it to pair (`No address for unknown device "17D491FC-…"`). It paged `00:00:00:00:00:00` on every claim. getkbd's own device object still reported the real address, so the zero-address check added in PR #25 never fired. When getkbd was relaunched, the new process paged the real address and claimed the keyboard in two seconds. An earlier run of the same failure, on 2026-11-09 from 09:45 to 11:19, matches this pattern.

The stale state therefore belongs to the getkbd process's Bluetooth session, not to anything getkbd can look up again. A new process is the only remedy observed to work.

## What Changes

- Notice when `bluetoothd` has restarted since getkbd started, by its process ID and start time. Check periodically, after wake, and before each keyboard claim or release.
- When it has restarted, relaunch getkbd. Do not relaunch while a keyboard operation is running; a claim or release that was due is done by the new instance, which re-evaluates the current signals at start as it already does.
- As a fallback for cases the process check misses, relaunch after two consecutive automatic claims in which Bluetooth gave no answer at all within the pairing timeout.
- Relaunch at most once every 10 minutes, so that a persistent fault cannot cause a relaunch loop. Log each detection and relaunch, and log why a relaunch was skipped.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `keyboard-handoff`: adds recovery from a Bluetooth service restart by relaunching getkbd.

## Impact

- A new small component reads `bluetoothd`'s process ID and start time with `sysctl` (no privileges needed) and decides when to relaunch. A relauncher starts the app bundle again once the current process has exited.
- `KeyboardController` reports when a pairing ends at getkbd's own timeout with no answer from Bluetooth. `OwnershipController` gains a gate that can hold back a keyboard operation while a relaunch is pending.
- Quitting already leaves the keyboard alone, and start-up already claims or releases according to the current signals, so a relaunch does not change ownership by itself.
- Relaunch works only when getkbd runs from an app bundle. A `swift run` build logs the detection and carries on.
- The menu does not change.
