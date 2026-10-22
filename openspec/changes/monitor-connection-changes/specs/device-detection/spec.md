## MODIFIED Requirements

### Requirement: Detect the configured external display while physically online

The system SHALL determine whether the configured display is online through local
CoreGraphics display services, including when it has been temporarily disabled
from the active desktop. Built-in displays SHALL be excluded from the selectable
desk-display list. The configured display SHALL be recognised under any display
identity it has been seen with, because macOS gives a monitor a different
identity for each cable or input it is connected through.

#### Scenario: External display is online

- **WHEN** the configured external display is present in the online display list
- **THEN** the display condition SHALL be present and getkbd SHALL notify the
  ownership controller

#### Scenario: Configured display is physically removed

- **WHEN** the configured external display is no longer online
- **THEN** the display condition SHALL be absent and getkbd SHALL notify the
  ownership controller

#### Scenario: Display changes settle

- **WHEN** macOS emits screen or display-reconfiguration events in quick
  succession
- **THEN** getkbd SHALL debounce evaluation using the configured interval, which
  defaults to 1.5 seconds, before publishing a changed physical condition

#### Scenario: Monitor is connected through a different cable or input

- **WHEN** no known identity of the configured display is online and exactly one
  online external display has the configured display's name
- **THEN** getkbd SHALL treat that display as the configured display and SHALL
  remember its identity as another connection of the same monitor

#### Scenario: Several displays share the monitor's name

- **WHEN** no known identity of the configured display is online and more than
  one online external display has its name
- **THEN** getkbd SHALL treat the configured display as absent

### Requirement: Detect physical USB hubs for KVM switching

The system SHALL observe connected USB host devices that expose USB device class 9,
track the presence of the selected hub group using stable descriptors, and
debounce that presence before notifying ownership logic. The hub group SHALL be
the hubs identified for every known connection of the configured monitor, SHALL
be present when any hub in the group is present, and SHALL be absent when none is
present.

#### Scenario: USB hub is connected

- **WHEN** a qualifying physical USB hub that belongs to the selected group is
  connected and remains present after debounce
- **THEN** getkbd SHALL mark the group present if it was absent and notify
  ownership logic

#### Scenario: Non-hub USB device is connected

- **WHEN** a USB device does not expose device class 9 or lacks vendor/product
  identifiers
- **THEN** getkbd SHALL ignore it for hub detection

#### Scenario: Selected hub is removed

- **WHEN** the last present hub in the selected group terminates and the group
  remains absent after debounce
- **THEN** getkbd SHALL mark the group absent and notify ownership logic

#### Scenario: One hub in the group is slower than another

- **WHEN** hubs in the group arrive or leave at slightly different times
- **THEN** getkbd SHALL report a single transition for the group rather than one
  per hub

#### Scenario: Hub has no serial number

- **WHEN** a qualifying hub has no serial number
- **THEN** its identifier SHALL be derived from its vendor, product, name, and
  manufacturer values

#### Scenario: Hub resembles the monitor's hubs but was never identified

- **WHEN** a hub with the same vendor and name as a hub in the group, but a
  different identifier, is connected
- **THEN** getkbd SHALL not treat it as part of the group

## ADDED Requirements

### Requirement: Learn the hub group of a new monitor connection

When setup is otherwise complete and the configured monitor is online through a
connection that has no hub group, the system SHALL identify that connection's hub
group from the next switch of the monitor to the other Mac and back, using the
same detection as monitor-switch setup, without the user opening Settings.

#### Scenario: User switches the monitor after changing cables

- **WHEN** the monitor is online through a connection with no hub group and one
  or more hubs change and return with a switch to the other Mac and back
- **THEN** getkbd SHALL save those hubs as that connection's hub group and SHALL
  keep the hub groups of other connections

#### Scenario: A switch is left half-finished

- **WHEN** hubs have changed once but have not returned within two minutes
- **THEN** getkbd SHALL discard that observation and SHALL wait for a new switch

#### Scenario: Connection changes before learning completes

- **WHEN** the monitor goes offline or comes online through a different
  connection while a hub group is being learned
- **THEN** getkbd SHALL stop learning for the previous connection
