## Why

getkbd currently asks users to configure monitor automation and USB hubs using
implementation-oriented terms, even though the meaningful choice is how they
switch the desk between Macs. KVM/input switching also cannot currently verify
from one Mac that the other Mac sees the complementary hub transition or that a
complete handoff succeeded. A guided, user-centered setup can make the existing
hub detection reliable to understand while explaining the new display-layout
protection during handoff.

## What Changes

- Replace the generic first-run settings path with a guided setup that asks
  whether the user physically swaps the display cable, changes the monitor input
  while both Macs remain connected, or switches manually.
- For monitor-input switching, explicitly pair with the other getkbd Mac over a
  local connection and present it as an `Other Mac` rather than exposing
  networking terminology.
- Correlate hub observations from both Macs while the user changes the monitor
  input, confirming that one hub follows the input and that it is visible on only
  one Mac at a time.
- Include an end-to-end KVM test before reporting the setup as ready. The test
  SHALL cover both directions where possible and verify keyboard handoff and
  display-layout protection/restoration. A skipped test remains visibly
  unverified.
- Explain that getkbd may temporarily mirror the built-in and shared displays
  while releasing the keyboard, and show progress for preparing the shared
  display, connecting the keyboard, and restoring the extended layout.
- Surface actionable states for peer-unavailable, no hub transition, multiple
  hub changes, both Macs seeing the hub, keyboard handoff failure, and display
  layout restoration failure.
- Keep local detection, manual switching, and the existing local handoff as
  fallbacks. Peer communication SHALL improve setup verification and status but
  SHALL not require a cloud service or become a dependency for ordinary local
  switching in this change.

## Capabilities

### New Capabilities

- `peer-verification`: Explicitly pair two local getkbd instances and exchange
  setup, readiness, hub-observation, and handoff-test state.

### Modified Capabilities

- `configuration-and-controls`: Replace generic onboarding with guided,
  source-specific setup; expose peer readiness, KVM test progress, display
  handoff status, and actionable recovery states.
- `device-detection`: Extend interactive USB hub identification with coordinated
  before/after observations from both Macs while retaining local fallback and
  unsafe-state reporting.
- `keyboard-handoff`: Make temporary display mirroring and layout restoration
  user-observable during handoff while preserving local Bluetooth ownership as
  the runtime fallback when peer communication is unavailable.

## Impact

- Affects the AppKit settings and menu-bar surfaces, onboarding state, device
  detection, ownership state reporting, and display handoff status.
- Extends the local architecture with an explicitly paired local-network
  communication path; no cloud service or remote ownership lock is introduced.
- Requires user-facing state modeling for peer availability, verification,
  KVM-test progress, and display-layout restoration outcomes.
- Requires focused tests for peer-unavailable and duplicate-hub cases, complete
  KVM test flows, local fallback behavior, and display handoff failure states.
