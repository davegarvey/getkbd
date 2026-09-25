# device-detection Specification

## Purpose

Define how getkbd discovers paired keyboards and identifies the selected external
display and physical KVM USB hub on the local Mac.

## Requirements

### Requirement: Discover paired Bluetooth keyboards

The system SHALL list locally paired Bluetooth devices that identify as a keyboard
by Bluetooth class or by a name containing "keyboard".

#### Scenario: Paired keyboard is available

- **WHEN** the settings window requests the keyboard list
- **THEN** getkbd SHALL return keyboard descriptors containing a stable device
  identifier and display name, sorted case-insensitively by name

#### Scenario: Non-keyboard device is paired

- **WHEN** a paired Bluetooth device is neither keyboard-class nor named as a
  keyboard
- **THEN** getkbd SHALL omit it from the selectable keyboard list

#### Scenario: Keyboard has no usable name

- **WHEN** a paired keyboard has an empty name
- **THEN** getkbd SHALL use its Bluetooth identifier as the display name

### Requirement: Detect the configured external display while physically online

The system SHALL determine whether the configured display is online through local
CoreGraphics display services, including when it has been temporarily disabled
from the active desktop. Built-in displays SHALL be excluded from the selectable
desk-display list.

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

### Requirement: Detect physical USB hubs for KVM switching

The system SHALL observe connected USB host devices that expose USB device class 9,
track the presence of the selected hub group using stable descriptors, and
debounce that presence before notifying ownership logic. The hub group SHALL be
present when any hub in the group is present and absent when none is present.

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

### Requirement: Refresh local device conditions from system events

The system SHALL observe local Bluetooth, display, USB, sleep, and wake events
without requiring a peer service or network connection.

#### Scenario: Unrelated Bluetooth device changes

- **WHEN** a Bluetooth device other than the selected keyboard connects or
  disconnects
- **THEN** getkbd SHALL not change the selected keyboard state

### Requirement: Identify the monitor's hub group locally

The system SHALL identify the monitor's hub group locally, without a peer
service, by observing which hubs change when the user switches the monitor to the
other Mac and back.

#### Scenario: Hubs leave and return with the switch

- **WHEN** during identification one or more hubs disappear after the first
  monitor switch and reappear after the second
- **THEN** getkbd SHALL select all of those hubs as the hub group

#### Scenario: Hubs arrive and leave with the switch

- **WHEN** identification starts while the monitor is showing the other Mac and
  one or more hubs appear after the first switch and disappear after the second
- **THEN** getkbd SHALL select all of those hubs as the hub group

#### Scenario: An unrelated device changes during identification

- **WHEN** a hub changes only once during identification, for example because a
  device was connected partway through
- **THEN** getkbd SHALL exclude that hub from the group

#### Scenario: No hub changes in both directions

- **WHEN** identification finishes or is cancelled and no hub changed in both
  directions
- **THEN** getkbd SHALL not change the stored hub group and SHALL report that the
  switch was not detected
