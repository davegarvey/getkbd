## Purpose

Define how getkbd claims and releases a selected Bluetooth keyboard and how
local automatic and manual ownership decisions are reconciled safely.

## ADDED Requirements

### Requirement: Claim and release the selected Bluetooth keyboard

The system SHALL make the selected Bluetooth keyboard connected to this Mac when
claiming it, and SHALL remove this Mac's Bluetooth pairing when releasing it so
the old Mac does not immediately reconnect.

#### Scenario: Claim an already connected keyboard

- **WHEN** the selected keyboard is already paired and connected to this Mac
- **THEN** a claim SHALL succeed without creating a new pairing

#### Scenario: Claim a keyboard from another Mac

- **WHEN** a claim is requested for a resolvable selected keyboard that is not
  connected locally
- **THEN** getkbd SHALL remove the local pairing if present, wait for the
  handoff to settle, pair the keyboard, open its connection, and verify that it
  is paired and connected locally

#### Scenario: Release a connected keyboard

- **WHEN** a release is requested for a resolvable selected keyboard
- **THEN** getkbd SHALL remove the local Bluetooth pairing and verify that the
  keyboard is neither paired nor connected to this Mac

#### Scenario: Keyboard cannot be resolved

- **WHEN** no keyboard is selected or the selected Bluetooth device cannot be
  resolved
- **THEN** the operation SHALL fail without claiming a device and SHALL expose
  a user-readable error

### Requirement: Report Bluetooth operation state and failures

The system SHALL expose connection states for the selected keyboard, serialize
Bluetooth operations, and report failed claims or releases instead of treating
them as successful.

#### Scenario: Operation is in progress

- **WHEN** a claim or release is running
- **THEN** the keyboard state SHALL indicate the corresponding in-progress state
  and another ownership operation SHALL wait until it finishes

#### Scenario: Bluetooth operation times out or verification fails

- **WHEN** pairing, connection, pairing removal, or connection verification
  times out or returns an error
- **THEN** the keyboard state SHALL become failed and the last error SHALL be
  available to the menu-bar UI

#### Scenario: Pairing requires user action

- **WHEN** Bluetooth requests numeric confirmation, a passkey, or a PIN
- **THEN** numeric confirmation SHALL be accepted automatically and getkbd SHALL
  activate an alert explaining how to type a passkey or PIN on the keyboard

### Requirement: Switch according to the configured ownership source

The system SHALL support monitor connection, KVM USB hub connection, and manual
only as mutually exclusive automatic sources.

#### Scenario: Monitor automation claims on connection

- **WHEN** monitor connection is the automatic source, the selected monitor is
  present, and claiming on monitor connection is enabled
- **THEN** getkbd SHALL request the keyboard and attribute the resulting
  ownership to the monitor

#### Scenario: Monitor automation releases its own claim

- **WHEN** the selected monitor disappears, monitor automation owns the
  keyboard, and release on monitor disconnect is enabled
- **THEN** getkbd SHALL request release and clear monitor ownership after a
  successful release

#### Scenario: Manual ownership survives monitor changes

- **WHEN** the keyboard was claimed manually and the selected monitor
  disconnects
- **THEN** getkbd SHALL keep the keyboard connected unless monitor takeover was
  explicitly enabled and a later monitor event transfers ownership

#### Scenario: Manual-only mode ignores automatic sensors

- **WHEN** the automatic source is manual only
- **THEN** monitor and USB hub events SHALL not claim or release the keyboard,
  while explicit Get Keyboard and Release Keyboard actions SHALL still work

### Requirement: Gate KVM automation on the monitor and selected USB hub

The system SHALL treat the selected monitor and selected USB hub as joint safety
conditions for KVM automation.

#### Scenario: KVM signal becomes active

- **WHEN** KVM USB hub automation is selected and both the selected monitor and
  selected USB hub are present
- **THEN** getkbd SHALL schedule a delayed claim for the selected keyboard and
  attribute ownership to the KVM USB hub

#### Scenario: KVM safety signal disappears

- **WHEN** KVM USB hub automation is selected and either the selected monitor or
  selected USB hub is absent
- **THEN** getkbd SHALL request release of the selected keyboard regardless of
  the monitor release preference

#### Scenario: KVM automation does not use the monitor claim preference

- **WHEN** KVM USB hub automation is selected
- **THEN** the monitor claim checkbox SHALL not be required for or control a KVM
  claim

#### Scenario: Both Macs see the selected hub

- **WHEN** the selected USB hub is simultaneously visible to both Macs
- **THEN** each local getkbd instance MAY consider its own KVM conditions ready,
  because getkbd provides no network arbitration or cross-Mac ownership lock

### Requirement: Reconcile ownership changes and retry automatic operations

The system SHALL converge toward the latest desired keyboard state after an
in-flight operation and SHALL retry eligible automatic failures a limited
number of times.

#### Scenario: Sensor reverses during a claim

- **WHEN** a monitor or KVM event requests release while a claim is in flight
- **THEN** getkbd SHALL finish the current operation and then reconcile toward
  the disconnected state

#### Scenario: Automatic operation fails temporarily

- **WHEN** an eligible automatic claim or release fails while its triggering
  condition remains valid
- **THEN** getkbd SHALL retry after a delay, up to two automatic retries, and
  SHALL stop retrying when the condition no longer applies

#### Scenario: Manual action overrides an automatic intent

- **WHEN** Get Keyboard or Release Keyboard is selected
- **THEN** getkbd SHALL replace pending automatic intent with the requested
  manual target state

### Requirement: Preserve and restore ownership across sleep

The system SHALL respond to system sleep and wake notifications according to the
release-before-sleep setting.

#### Scenario: Release before sleep is enabled

- **WHEN** the Mac is preparing to sleep and release before sleep is enabled
- **THEN** getkbd SHALL attempt to release the selected keyboard and clear its
  active ownership intent

#### Scenario: Release before sleep is disabled

- **WHEN** the Mac is preparing to sleep and release before sleep is disabled
- **THEN** getkbd SHALL not initiate a sleep-triggered release

#### Scenario: Mac wakes

- **WHEN** the Mac wakes
- **THEN** getkbd SHALL refresh the keyboard state and re-evaluate the current
  monitor and KVM conditions before deciding whether to reclaim or preserve the
  connection

### Requirement: Change keyboard selection without orphaning the old device

The system SHALL release the currently connected selected keyboard before
applying a different keyboard selection.

#### Scenario: Previous keyboard releases successfully

- **WHEN** the selected keyboard is changed while the previous keyboard is
  connected locally
- **THEN** getkbd SHALL release the previous keyboard, apply the new selection,
  and evaluate the configured automatic conditions for the new keyboard

#### Scenario: Previous keyboard cannot be released

- **WHEN** release of the previous keyboard fails during a selection change
- **THEN** getkbd SHALL keep the previous selection, restore its ownership
  state, and show a user-readable reconfiguration error

### Requirement: Keep switching local and signal-driven

The system SHALL use local Bluetooth, display, USB, and system lifecycle signals
for handoff and SHALL not require network communication or normal keyboard or
mouse input as a switching signal.

#### Scenario: Network is unavailable

- **WHEN** the Mac has no network connectivity
- **THEN** local manual and automatic handoff behavior SHALL not depend on the
  network
