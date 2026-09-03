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
- **THEN** getkbd SHALL schedule a delayed keyboard claim attributed to the USB hub

#### Scenario: KVM safety signal disappears

- **WHEN** the selected display is offline or the selected USB hub is absent
- **THEN** getkbd SHALL request release of the selected keyboard regardless of any
  manual preference and SHALL leave display configuration unchanged

#### Scenario: Both Macs see the selected hub

- **WHEN** the selected USB hub is simultaneously visible to both Macs
- **THEN** each local instance SHALL rely only on its local signal and SHALL not
  claim that a remote ownership lock exists

#### Scenario: Hub presence flaps during an input switch

- **WHEN** USB notifications rapidly alternate between present and absent
- **THEN** getkbd SHALL debounce the selected-hub condition before changing the
  automatic ownership target

### Requirement: Preserve display configuration during handoff

During keyboard handoff, getkbd SHALL preserve display enablement, mirroring,
display modes, and the relative arrangement of displays. For configured KVM
automation, getkbd SHALL use the stable selected USB hub signal to choose the
preferred primary display: the selected external display when the hub is present,
or the active built-in display when the hub is absent. getkbd SHALL not enumerate,
move, or persist application windows; macOS SHALL remain responsible for normal
window relocation resulting from a primary-display change.

#### Scenario: USB hub changes while the display remains online

- **WHEN** the selected USB hub appears or disappears while the selected display
  remains online
- **THEN** getkbd SHALL synchronize the preferred primary display according to the
  stable hub condition, SHALL proceed with the existing keyboard ownership
  behavior, and SHALL leave display enablement, mirroring, modes, and relative
  arrangement unchanged

#### Scenario: USB hub disappears while the built-in display is active

- **WHEN** the selected USB hub becomes stably absent while the selected display
  remains online and the built-in display is active
- **THEN** getkbd SHALL make the built-in display primary, SHALL proceed with the
  existing keyboard ownership behavior, and SHALL leave display enablement,
  mirroring, modes, and relative arrangement unchanged

#### Scenario: USB hub disappears during clamshell use

- **WHEN** the selected USB hub becomes stably absent while the selected display
  remains online and the built-in display is inactive
- **THEN** getkbd SHALL not attempt to make the built-in display primary and SHALL
  leave the active external display configuration unchanged

#### Scenario: User manually releases the keyboard

- **WHEN** the user chooses Release Keyboard
- **THEN** getkbd SHALL release the keyboard without changing the preferred primary
  display solely because of the manual action

#### Scenario: Closed-lid active use

- **WHEN** the Mac has no active built-in display but the selected external display
  and USB hub are present
- **THEN** getkbd SHALL allow the external display to remain enabled and primary,
  SHALL not require mirroring, and SHALL not attempt to activate the built-in
  display

#### Scenario: Selected display is offline

- **WHEN** the selected display is not online
- **THEN** getkbd SHALL not attempt display configuration and SHALL not
  automatically claim the keyboard

#### Scenario: Primary-display configuration fails

- **WHEN** macOS rejects or cannot verify a requested primary-display change
- **THEN** getkbd SHALL leave keyboard claim or release behavior independent of
  that failure and SHALL not fail an otherwise eligible keyboard handoff because
  of display-role configuration

#### Scenario: Application-scoped display role ends

- **WHEN** getkbd terminates after applying a primary-display change
- **THEN** getkbd SHALL not persist that primary-display change as permanent
  display configuration

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

The system SHALL release the keyboard before sleep and re-evaluate local
conditions after wake or application restart. When the selected display and
signals are available, this re-evaluation SHALL also synchronize the preferred
primary display without changing display modes, enablement, mirroring, or relative
arrangement.

#### Scenario: Mac prepares to sleep

- **WHEN** the Mac is preparing to sleep
- **THEN** getkbd SHALL release the selected keyboard, cancel pending automatic
  claims, and SHALL not attempt a primary-display change during sleep preparation

#### Scenario: Mac wakes

- **WHEN** the Mac wakes
- **THEN** getkbd SHALL refresh the keyboard state and re-evaluate the selected
  display and USB hub before deciding whether to reclaim the keyboard or update the
  preferred primary display

#### Scenario: Application starts or restarts

- **WHEN** getkbd starts with configured display and USB-hub selections
- **THEN** getkbd SHALL evaluate the current local signals and synchronize the
  preferred primary display without waiting for a new USB transition

#### Scenario: Application quits

- **WHEN** getkbd quits
- **THEN** getkbd SHALL not release the keyboard as a quit side effect and SHALL
  not persist an application-scoped primary-display change as permanent display
  configuration

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
