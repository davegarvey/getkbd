## MODIFIED Requirements

### Requirement: Learn each Mac's monitor input

The system SHALL learn the monitor input number for this Mac and for the other
Mac by reading the input after each settled hub-group state and at launch. A
reading SHALL be accepted only when two consecutive readings agree. Input numbers
SHALL be learned and kept separately for each connection of the monitor, and SHALL
not be learned for a connection that has no hub group.

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

#### Scenario: Current connection has no hub group

- **WHEN** the monitor is online through a connection whose hub group has not
  been learned
- **THEN** getkbd SHALL not learn input numbers and SHALL not offer a monitor
  action

#### Scenario: Cables are swapped back

- **WHEN** the monitor is online again through a connection whose inputs were
  learned earlier
- **THEN** getkbd SHALL use that connection's learned inputs without learning
  them again
