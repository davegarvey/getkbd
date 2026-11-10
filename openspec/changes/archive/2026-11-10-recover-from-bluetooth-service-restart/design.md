## Context

getkbd talks to Bluetooth through IOBluetooth, which reaches `bluetoothd` over XPC sessions that the framework re-creates when `bluetoothd` restarts. After the restart on 2026-11-10, `bluetoothd` held no address for the device UUID that the getkbd process used. Pairing then paged `00:00:00:00:00:00` and the pairing delegate never reported a result, so each claim ended at getkbd's 45-second timeout with `kIOReturnError`. The `IOBluetoothDevice` object, including a fresh `IOBluetoothDevice(addressString:)` lookup, still reported the real address, so nothing inside the process exposed the fault. A relaunched process using the same UUID paged the right address.

Start-up already reconciles ownership from the current display and hub signals (claim if the hub is present, release if absent and the keyboard is paired), and quitting already leaves the keyboard untouched. A relaunch therefore needs no ownership hand-over.

## Goals / Non-Goals

**Goals:**
- Recover automatically from a `bluetoothd` restart without a power cycle or manual relaunch.
- Catch the restart before the first claim that would fail, because the keyboard is pairable for only a minute or two after the other Mac releases it.
- Never loop, and never interrupt a running claim or release or a sleep transition.

**Non-Goals:**
- Repairing the session in-process. No API to do so is known, and the 2026-11-09 recovery through discovery was seen only once.
- Reading the unified log for `No address for unknown device`, which needs privileges the app does not have.
- Menu changes.

## Decisions

**Identify `bluetoothd` by PID and start time.** `sysctl(KERN_PROC_ALL)` lists processes without privileges (tested on this Mac). Comparing the start time as well as the PID guards against PID reuse. If `bluetoothd` is briefly absent, the check reports no change. Its replacement will have a new identity on the next check. Alternative considered: observing `CBCentralManager` state going through `.resetting`. It is undocumented whether that fires for a daemon crash, and it would add a CoreBluetooth manager just for this.

**When to check.** Every 30 seconds while awake (one `sysctl` call), after system wake, before each claim, and after each operation finishes. The check before a claim is the one that matters for the observed failure. The timer makes recovery happen while idle, so the first claim after a restart runs without delay.

**Claims are gated; releases are not.** `OwnershipController` asks a gate before starting a claim. When a relaunch is due, the gate starts it and the claim is not begun; the new instance claims at start. A release goes ahead and the relaunch follows once it finishes. This is because the failure has been observed only for pairing, and holding back a release could leave the keyboard bonded here. Releases before sleep are unaffected, and relaunches are deferred while the Mac is preparing to sleep or asleep.

**Fallback on unanswered claims.** `pairDevice` returns `kIOReturnTimeout` instead of `kIOReturnError` when getkbd's own deadline expires with no delegate result. Two consecutive automatic claims ending that way cause a relaunch. A keyboard that is simply out of reach fails differently: Bluetooth reports page timeout (`IOReturn 4`) after about 16 seconds. Manual claims do not count, so a user waiting on a pairing prompt is never relaunched away from it.

**Rate limit through `UserDefaults`.** The time of the last relaunch is stored under `lastBluetoothRelaunchAt`, and no relaunch happens within 10 minutes of it. A skipped relaunch is logged once per detection. The stored time survives the relaunch, which is what makes the limit effective.

**Relaunch mechanism.** If `Bundle.main.bundleURL` is an `.app`, getkbd starts `/bin/sh` with a short script. The script waits for the current PID to exit, then runs `/usr/bin/open` on the bundle. getkbd then calls `NSApp.terminate`. Waiting for the exit avoids two instances acting on the keyboard at once. `NSWorkspace` with `createsNewApplicationInstance` was rejected because it overlaps the instances. Outside a bundle, getkbd logs and carries on.

**Decision logic is a pure value type** (`BluetoothRecoveryPolicy`), so the checks harness can cover it without IOBluetooth or AppKit.

## Risks / Trade-offs

- [A relaunch adds about a second before a claim] → The claim settle delay already exists, and a claim that would page zero fails outright.
- [The fallback misfires on some other fault that makes pairing hang] → It is limited to automatic claims and one relaunch per 10 minutes. A relaunch is harmless to ownership.
- [Logging a `bluetoothd` restart every 30 s during the rate-limit window] → Log a skipped relaunch once per detected identity.
- [Untestable end to end on demand] → Restarting `bluetoothd` needs root (`sudo pkill bluetoothd`). The user can do it once on one Mac to verify. Otherwise the policy is covered by checks, and the logs will show the next natural restart.
