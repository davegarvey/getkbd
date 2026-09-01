# keyboard-handoff Specification

## MODIFIED Requirements

### Requirement: Gate KVM automation on the monitor and selected USB hub

The system SHALL treat the selected monitor and selected USB hub as joint local
safety conditions for monitor-input automation. Peer verification MAY confirm
the setup but SHALL not replace those local conditions for ownership decisions.

#### Scenario: KVM signal becomes active

- **WHEN** monitor-input automation is selected and both the selected monitor and
  selected USB hub are present locally
- **THEN** getkbd SHALL schedule a delayed claim for the selected keyboard and
  attribute ownership to the USB hub signal

#### Scenario: KVM safety signal disappears

- **WHEN** monitor-input automation is selected and either the selected monitor
  or selected USB hub is absent locally
- **THEN** getkbd SHALL request release of the selected keyboard regardless of
  the monitor release preference

#### Scenario: KVM automation does not use the monitor claim preference

- **WHEN** monitor-input automation is selected
- **THEN** the monitor claim checkbox SHALL not be required for or control a KVM
  claim

#### Scenario: Both Macs see the selected hub

- **WHEN** the selected USB hub is simultaneously visible to both Macs
- **THEN** each local instance MAY consider its own local KVM conditions ready,
  because getkbd provides no remote ownership lock, but paired verification SHALL
  mark the setup unsafe and SHALL not report it as verified

### Requirement: Keep switching local and signal-driven

The system SHALL use local Bluetooth, display, USB, and system lifecycle signals
for ordinary handoff. Optional peer communication MAY verify setup and report
status, but SHALL not be required for local manual or automatic switching.

#### Scenario: Network is unavailable

- **WHEN** the Mac has no network connectivity or the peer is unavailable
- **THEN** local manual and automatic handoff behavior SHALL not depend on the
  peer connection

#### Scenario: Peer verification becomes stale

- **WHEN** a paired peer stops responding during or after setup
- **THEN** getkbd SHALL mark peer verification stale without changing an already
  local ownership decision solely because of the stale state

## ADDED Requirements

### Requirement: Protect the shared display during keyboard release

When a keyboard release occurs while the selected external display remains
attached and a built-in display is available, getkbd SHALL make the built-in
laptop display primary, temporarily mirror the selected external display onto
it, and SHALL retain the prior extended layout for restoration. The laptop SHALL
remain the mirror master while this Mac is inactive.

#### Scenario: Display remains attached during release

- **WHEN** getkbd releases the keyboard while the selected external display and
  an active built-in display remain available
- **THEN** getkbd SHALL make the laptop primary before enabling the display
  mirror, prepare that mirror before or as part of the release, and SHALL expose
  a display-protection phase to the UI

#### Scenario: Keyboard is claimed after protected release

- **WHEN** this Mac successfully claims the keyboard after a protected release
- **THEN** getkbd SHALL disable the temporary mirror, restore the saved extended
  display layout and display modes, make the selected monitor primary, and only
  then report the layout restored

#### Scenario: No display can be mirrored

- **WHEN** the selected display has disappeared, the displays are already
  mirrored, or no active built-in display is available
- **THEN** the keyboard release SHALL proceed without attempting a mirror and the
  UI SHALL not report a false display-protection success

#### Scenario: Display restoration fails

- **WHEN** getkbd cannot restore the saved display layout or selected primary
  monitor after a successful keyboard claim
- **THEN** the UI SHALL show an attention state with a retry or Display Settings
  recovery path while preserving the keyboard result

### Requirement: Report display handoff progress

The system SHALL expose user-readable display handoff states for preparing,
protected, restoring, restored, and attention-required outcomes.

#### Scenario: Display handoff is in progress

- **WHEN** display mirroring or restoration is running
- **THEN** the menu-bar and guided setup surfaces SHALL identify the current
  phase instead of showing only a generic Bluetooth operation state

#### Scenario: Display handoff completes

- **WHEN** the expected mirror or restored extended layout is verified
- **THEN** getkbd SHALL clear the transient phase and retain a concise successful
  status for the current handoff
