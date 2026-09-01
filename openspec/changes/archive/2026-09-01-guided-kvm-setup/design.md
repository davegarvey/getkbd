## Context

See `proposal.md` for the motivation and user-facing scope. The current app has
local display, USB, Bluetooth, and ownership observers, plus a programmatic
AppKit settings window and menu-bar interface. The latest implementation also
temporarily mirrors the built-in and selected external displays while releasing
the keyboard and restores the saved extended layout after a successful claim.

The current architecture has no peer transport, no persisted peer identity, and
no user-facing state for display-layout handoff. Existing local observers must
continue to work when the other Mac, the local network, or peer verification is
unavailable.

## Goals / Non-Goals

**Goals:**

- Make first-run setup describe the physical desk action instead of exposing
  monitor/KVM implementation terminology.
- Add explicit, friendly pairing with the other local getkbd instance for KVM
  setup verification and end-to-end testing.
- Correlate local and remote USB-hub observations without moving ownership
  decisions out of the existing local state machine.
- Make display preparation, temporary mirroring, layout restoration, and their
  failures visible and recoverable.
- Preserve local/manual operation as a fallback when peer verification is not
  available.

**Non-Goals:**

- Do not add cloud services, accounts, remote keyboard control, or a distributed
  ownership lock in this change.
- Do not make ordinary local monitor, USB-hub, or manual switching depend on the
  peer connection.
- Do not synchronize all application settings automatically between Macs.
- Do not replace the existing local USB-hub identification fallback.

## Decisions

### Use physical setup language in the guided flow

The first choice will be based on desk topology: the user either unplugs and
reconnects a display cable, changes the monitor input while both Macs remain
connected, or switches manually. The existing automatic-source values remain
the internal behavior model, but their primary labels and help text use these
physical descriptions.

### Use an optional paired local peer channel

The peer service will advertise a getkbd instance on the local network, discover
other instances, and establish a connection only after the user explicitly
confirms the same short code on both Macs. A stable per-installation instance
identifier and the paired peer identifier will be persisted separately from the
existing application settings so older settings decode unchanged.

The initial transport will use system local-network services and a small,
versioned Codable message protocol. The app will request the macOS local-network
permission with an explanation that it is only used to verify the other Mac.
The protocol will exchange setup/status data and hub observations, never
Bluetooth credentials or keyboard input.

### Keep local ownership authoritative

`OwnershipController` will continue to make claim/release decisions from local
display, USB, sleep, and Bluetooth state. Peer messages update verification,
readiness, and test state only. If the peer disappears, local behavior continues
and the UI changes to an unverified or unavailable state instead of interrupting
an in-progress handoff.

### Correlate hub transitions by session and stable descriptor

Starting KVM detection creates a session identifier and records a local hub
snapshot. The paired Mac records its corresponding snapshot. Each side sends
subsequent hub snapshots with the session identifier. A transition is verified
only when the same stable hub descriptor appears on one side and disappears on
the other, with no competing hub changes. Local-only detection remains usable
when the peer is unavailable.

### Make the KVM test a guided, user-driven state machine

The setup UI will provide a `Test switching` action after hub detection. It will
tell the user to change the monitor input, display local and remote progress, and
ask the user to perform the reverse direction. The test is complete only after
both directions pass where both Macs are available. A user may continue without
the test, but the configuration remains visibly unverified.

### Expose display handoff state without adding a new default-off setting

The existing display mirroring behavior remains automatic. `DisplayMonitor`
will expose a small state and error surface to the ownership/UI layers:
preparing, protected, restoring, restored, and attention-required. The saved
layout remains internal and is never sent to the peer. A restoration failure
must be visible with a path to Display Settings or a retry action.

### Use progressive disclosure in the settings window

The guided setup summary and source-specific requirements appear first. The raw
USB-hub selector remains available as a manual fallback, while technical device
identifiers and advanced behavior options remain secondary. The menu-bar menu
shows the current ownership action first, followed by compact readiness,
peer-verification, and display-handoff status.

## Risks / Trade-offs

- [Risk] Local-network discovery can be blocked by macOS permission, firewall,
  Wi-Fi isolation, or a sleeping Mac. -> Keep peer verification optional,
  explain the unavailable state, and retain local detection and manual control.
- [Risk] A wrong local peer could be selected. -> Show the Mac name and require
  matching short-code confirmation on both instances before exchanging state.
- [Risk] Matching hub descriptors can be ambiguous when hardware lacks a serial
  number. -> Require complementary before/after observations, reject multiple
  changes, and retain manual selection.
- [Risk] Temporary display mirroring can surprise users or fail to restore. ->
  Explain it before the KVM test, show live phases, retain an attention state,
  and provide retry/System Settings recovery.
- [Risk] Peer state can be stale during a handoff. -> Include session IDs and
  timestamps, treat local observations as authoritative for local actions, and
  never claim that peer verification is current after the connection is lost.
- [Risk] The first implementation expands the app's surface area substantially.
  -> Avoid settings synchronization and remote arbitration until this setup and
  verification path is stable.

## Migration Plan

1. Ship the new guided flow and peer service with existing local behavior as the
   fallback.
2. Add the local-network usage description and Bonjour service declaration to the
   packaged app.
3. Treat existing saved settings as unpaired and preserve their current source
   and device selections.
4. If peer data is removed or cannot be decoded, clear only peer verification
   state; do not discard application settings.
5. Rollback consists of disabling peer verification and using the existing local
   hub-identification and handoff paths; no Bluetooth data migration is needed.
