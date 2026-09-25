## Purpose

Let getkbd switch the selected monitor between the two Macs' inputs over the
display connection, learning which input belongs to each Mac without user input.

## ADDED Requirements

### Requirement: Reach the selected monitor's input control

The system SHALL read and change the input source (MCCS VCP code 0x60) of the
selected external display over its display connection using only interfaces
built into macOS. It SHALL identify the display's control channel by matching the
display's vendor, model and serial numbers, and SHALL treat the monitor as
unreachable when no channel matches uniquely.

#### Scenario: Monitor responds

- **WHEN** the selected display is online and answers an input-source query
- **THEN** getkbd SHALL treat the monitor's input control as available

#### Scenario: Monitor does not respond

- **WHEN** the query fails, returns a malformed reply, or the control channel
  cannot be identified
- **THEN** getkbd SHALL treat the input control as unavailable and SHALL not
  affect keyboard handoff or primary-display behaviour

#### Scenario: Monitor is temporarily busy

- **WHEN** the monitor does not answer while it is changing input
- **THEN** getkbd SHALL retry within a bounded period before treating the
  reading as unavailable

### Requirement: Learn each Mac's monitor input

The system SHALL learn the monitor input number for this Mac and for the other
Mac by reading the input after each settled hub-group state and at launch. A
reading SHALL be accepted only when two consecutive readings agree.

#### Scenario: Hub group is present

- **WHEN** the hub group is stably present and the monitor reports an accepted
  input number
- **THEN** getkbd SHALL record it as this Mac's input

#### Scenario: Hub group is absent

- **WHEN** the hub group is stably absent, the selected display is online, and
  the monitor reports an accepted input number
- **THEN** getkbd SHALL record it as the other Mac's input

#### Scenario: Readings conflict

- **WHEN** an accepted reading would make this Mac's input equal to the other
  Mac's input
- **THEN** getkbd SHALL discard the reading and keep the previously learned
  values

#### Scenario: Selected display changes

- **WHEN** the user selects a different display
- **THEN** getkbd SHALL discard the learned inputs and learn them again for the
  new display

### Requirement: Switch the monitor between Macs

The system SHALL send a single input-change command when the user chooses a
monitor action, and SHALL rely on the existing hub-group signal for the resulting
keyboard handoff and primary-display change.

#### Scenario: Switch to the other Mac

- **WHEN** the user chooses Switch Monitor to Other Mac
- **THEN** getkbd SHALL set the monitor's input to the other Mac's learned input

#### Scenario: Switch to this Mac

- **WHEN** the user chooses Switch Monitor to This Mac
- **THEN** getkbd SHALL set the monitor's input to this Mac's learned input

#### Scenario: The monitor does not switch

- **WHEN** the command fails or the hub group does not change within 15 seconds
- **THEN** getkbd SHALL log the failure and SHALL leave keyboard ownership
  unchanged
