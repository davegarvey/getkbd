# keyboard-handoff Specification

## Purpose

Define how getkbd moves one locally paired Bluetooth keyboard between two Macs
using the selected monitor KVM's local USB hub signal.

## Requirements

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
- **THEN** the operation SHALL fail without claiming a device and SHALL expose a
  user-readable error

### Requirement: Use the local KVM USB hub as the automatic ownership signal

The system SHALL treat the selected physical USB hub as the automatic active-input
signal. The selected external display SHALL be a joint safety condition, not an
ownership signal. Automatic claim readiness SHALL require the Mac to be awake,
the selected display to be online, and the selected USB hub to be present locally.

#### Scenario: KVM signal becomes active

- **WHEN** the selected display is online and the selected USB hub becomes stably
  present locally while the Mac is awake
- **THEN** getkbd SHALL restore the external display layout and SHALL schedule a
  delayed keyboard claim attributed to the USB hub

#### Scenario: KVM safety signal disappears

- **WHEN** the selected display is offline or the selected USB hub is absent
- **THEN** getkbd SHALL park the external display when possible and SHALL request
  release of the selected keyboard regardless of any manual preference

#### Scenario: Both Macs see the selected hub

- **WHEN** the selected USB hub is simultaneously visible to both Macs
- **THEN** each local instance SHALL rely only on its local signal and SHALL not
  claim that a remote ownership lock exists

#### Scenario: Hub presence flaps during an input switch

- **WHEN** USB notifications rapidly alternate between present and absent
- **THEN** getkbd SHALL debounce the selected-hub condition before changing the
  automatic ownership target

### Requirement: Park the external display without mirroring

When the automatic target is inactive and the selected external display remains
online, getkbd SHALL disable that display in the local WindowServer desktop rather
than mirror it with another display. getkbd SHALL retain the active extended
layout and display modes for restoration. Parking SHALL not select a new display
mode or inherit scaling from another display.

#### Scenario: Inactive Mac still sees the external display

- **WHEN** the selected USB hub disappears while the external display remains
  physically online
- **THEN** getkbd SHALL park the external display even if the keyboard is already
  disconnected, so macOS can re-home windows onto the laptop display

#### Scenario: Display is parked

- **WHEN** the external display is parked
- **THEN** the display SHALL remain physically online for the monitor KVM and USB
  hub, while it is excluded from this Mac's active desktop

#### Scenario: Mac becomes active again

- **WHEN** the selected display and USB hub are online and present locally
- **THEN** getkbd SHALL enable the external display, restore the saved extended
  layout and display modes, make the external display primary, and then allow
  the keyboard claim to proceed

#### Scenario: Closed-lid active use

- **WHEN** the Mac has no active built-in display but the selected external display
  and USB hub are present
- **THEN** getkbd SHALL allow the external display to remain enabled and SHALL
  not require mirroring

#### Scenario: Display parking is unavailable

- **WHEN** the private display-enable operation is unavailable or fails
- **THEN** getkbd SHALL still complete the keyboard ownership operation when
  possible and SHALL expose an attention state with a Display Settings recovery
  path

#### Scenario: Selected display is offline

- **WHEN** the selected display is not online
- **THEN** getkbd SHALL not attempt display configuration and SHALL not
  automatically claim the keyboard

### Requirement: Report display parking progress

The system SHALL expose user-readable display states for parking, parked,
restoring, restored, and attention-required outcomes.

#### Scenario: Display parking is in progress

- **WHEN** getkbd is enabling or disabling the selected external display
- **THEN** the menu-bar and settings surfaces SHALL identify the current phase

#### Scenario: Display parking completes

- **WHEN** the expected enabled or parked state is verified
- **THEN** getkbd SHALL expose the corresponding successful state

### Requirement: Reconcile ownership changes and retry automatic operations

The system SHALL converge toward the latest desired keyboard state after an
in-flight operation and SHALL retry eligible automatic failures a limited number
of times.

#### Scenario: Sensor reverses during a claim

- **WHEN** the USB hub disappears while a claim is in flight
- **THEN** getkbd SHALL finish the current operation and then reconcile toward the
  disconnected state

#### Scenario: Automatic operation fails temporarily

- **WHEN** an automatic claim or release fails while its triggering condition
  remains valid
- **THEN** getkbd SHALL retry after a delay, up to two automatic retries, and
  SHALL stop retrying when the condition no longer applies

#### Scenario: Manual action overrides an automatic intent

- **WHEN** Get Keyboard or Release Keyboard is selected
- **THEN** getkbd SHALL replace the current automatic target with the requested
  manual target until a subsequent local sensor transition or restart

### Requirement: Preserve safe behavior across sleep and restart

The system SHALL release the keyboard before sleep, park the external display when
possible, and re-evaluate local conditions after wake or application restart.

#### Scenario: Mac prepares to sleep

- **WHEN** the Mac is preparing to sleep
- **THEN** getkbd SHALL release the selected keyboard and cancel pending automatic
  claims

#### Scenario: Mac wakes

- **WHEN** the Mac wakes
- **THEN** getkbd SHALL refresh the keyboard state and re-evaluate the selected
  display and USB hub before deciding whether to reclaim the keyboard

#### Scenario: Application quits

- **WHEN** getkbd quits while the external display is parked
- **THEN** getkbd SHALL restore the external display configuration without
  releasing the keyboard as a quit side effect

### Requirement: Change keyboard selection without orphaning the old device

The system SHALL release the currently connected selected keyboard before applying
a different keyboard selection.

#### Scenario: Previous keyboard releases successfully

- **WHEN** the selected keyboard is changed while the previous keyboard is
  connected locally
- **THEN** getkbd SHALL release the previous keyboard, apply the new selection,
  and evaluate the current local KVM conditions for the new keyboard

#### Scenario: Previous keyboard cannot be released

- **WHEN** release of the previous keyboard fails during a selection change
- **THEN** getkbd SHALL keep the previous selection and show a user-readable
  reconfiguration error

### Requirement: Keep ordinary switching local and signal-driven

The system SHALL use only local Bluetooth, USB, display, sleep, and wake signals
for ordinary automatic and manual handoff. It SHALL not require a network
connection, paired peer, remote lock, or remote status exchange.

#### Scenario: Network is unavailable

- **WHEN** the Mac has no network connectivity
- **THEN** local manual and automatic handoff behavior SHALL continue normally
