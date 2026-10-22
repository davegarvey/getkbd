## MODIFIED Requirements

### Requirement: Learn each Mac's monitor input

The system SHALL learn the monitor input number for this Mac and for the other
Mac by reading the input after each settled hub-group state and at launch. A
reading SHALL be accepted only when two consecutive readings agree. Input numbers
SHALL be learned and kept separately for each connection of the monitor.

#### Scenario: Hub group is present

- **WHEN** the hub group is stably present and the monitor reports an accepted
  input number
- **THEN** getkbd SHALL record it as this Mac's input for the current connection

#### Scenario: Hub group is absent

- **WHEN** the hub group is stably absent, the selected display is online, and
  the monitor reports an accepted input number
- **THEN** getkbd SHALL record it as the other Mac's input for the current
  connection

#### Scenario: Readings conflict

- **WHEN** an accepted reading would make this Mac's input equal to the other
  Mac's input
- **THEN** getkbd SHALL discard the reading and keep the previously learned
  values

#### Scenario: Selected display changes

- **WHEN** the user selects a different display
- **THEN** getkbd SHALL discard the learned inputs and learn them again for the
  new display

#### Scenario: One input is learned on a new connection

- **WHEN** an input is learned for a connection that lacks the other Mac's input,
  and another connection's learned pair contains that input
- **THEN** getkbd SHALL take the other value of that pair as the missing input

#### Scenario: Cables are swapped back

- **WHEN** the monitor is online again through a connection whose inputs were
  learned earlier
- **THEN** getkbd SHALL use that connection's learned inputs without learning
  them again

### Requirement: Switch the monitor between Macs

The system SHALL send a single input-change command when the user chooses a
monitor action, and SHALL rely on the existing hub-group signal for the resulting
keyboard handoff and primary-display change. The command SHALL use the inputs
learned for the connection the monitor is currently online through.

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

#### Scenario: Switch after the cables are swapped

- **WHEN** the cables to the two Macs have been swapped, the monitor is showing
  this Mac, and this Mac's input has been read on the new connection
- **THEN** getkbd SHALL offer Switch Monitor to Other Mac without first needing
  the monitor to be switched by other means
