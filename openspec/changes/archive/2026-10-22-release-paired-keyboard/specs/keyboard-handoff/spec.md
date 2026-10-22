## MODIFIED Requirements

### Requirement: Use the local KVM USB hub as the automatic ownership signal

The system SHALL treat the presence of the selected USB hub group as the automatic
active-input signal. The selected external display SHALL be a joint safety
condition, not an ownership signal. Automatic claim readiness SHALL require the
Mac to be awake, the selected display to be online, and the hub group to be
present locally.

#### Scenario: KVM signal becomes active

- **WHEN** the selected display is online and the hub group becomes stably
  present locally while the Mac is awake
- **THEN** getkbd SHALL schedule a delayed keyboard claim attributed to the USB hub

#### Scenario: KVM safety signal disappears

- **WHEN** the selected display is offline or the hub group is absent
- **THEN** getkbd SHALL request release of the selected keyboard regardless of any
  manual preference and SHALL leave display configuration unchanged

#### Scenario: Keyboard is paired but not connected

- **WHEN** release is required and the selected keyboard is paired to this Mac
  but not connected, for example because Bluetooth was off or the keyboard is
  asleep
- **THEN** getkbd SHALL remove this Mac's pairing as it would for a connected
  keyboard

#### Scenario: Bluetooth comes back on

- **WHEN** Bluetooth becomes available, release is required, and the selected
  keyboard is still paired to this Mac
- **THEN** getkbd SHALL remove the pairing without waiting for another signal
  change

#### Scenario: Both Macs see the selected hub

- **WHEN** a hub in the group is simultaneously visible to both Macs
- **THEN** each local instance SHALL rely only on its local signal and SHALL not
  claim that a remote ownership lock exists

#### Scenario: Hub presence flaps during an input switch

- **WHEN** USB notifications rapidly alternate between present and absent
- **THEN** getkbd SHALL debounce the hub-group condition before changing the
  automatic ownership target

### Requirement: Change keyboard selection without orphaning the old device

The system SHALL release the currently selected keyboard before applying a
different keyboard selection when that keyboard is connected or paired locally.

#### Scenario: Previous keyboard releases successfully

- **WHEN** the selected keyboard is changed while the previous keyboard is
  connected or paired locally
- **THEN** getkbd SHALL release the previous keyboard, apply the new selection,
  and evaluate the current local KVM conditions for the new keyboard

#### Scenario: Previous keyboard cannot be released

- **WHEN** release of the previous keyboard fails during a selection change
- **THEN** getkbd SHALL keep the previous selection and show a user-readable
  reconfiguration error
