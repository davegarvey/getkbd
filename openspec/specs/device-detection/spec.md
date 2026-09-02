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

The system SHALL list connected USB host devices that expose USB device class 9,
track presence of the selected hub using a stable descriptor, and debounce its
presence before notifying ownership logic.

#### Scenario: USB hub is connected

- **WHEN** a qualifying physical USB hub is connected
- **THEN** getkbd SHALL expose its name, manufacturer, vendor ID, product ID, and
  identifier in the settings list and update its selected-presence condition

#### Scenario: Non-hub USB device is connected

- **WHEN** a USB device does not expose device class 9 or lacks vendor/product
  identifiers
- **THEN** getkbd SHALL omit it from the KVM hub list

#### Scenario: Selected hub is removed

- **WHEN** the selected USB hub terminates and remains absent after debounce
- **THEN** getkbd SHALL mark it absent, refresh the hub list, and notify ownership
  logic

#### Scenario: Hub has no serial number

- **WHEN** a qualifying hub has no serial number
- **THEN** its identifier SHALL be derived from its vendor, product, name, and
  manufacturer values

### Requirement: Identify the selected hub locally

The system SHALL support local before-and-after hub identification without a peer
service.

#### Scenario: Local identification finds exactly one changed hub

- **WHEN** the user starts hub identification and exactly one local hub identifier
  changes
- **THEN** getkbd SHALL select that changed hub

#### Scenario: Several hubs change during identification

- **WHEN** more than one hub identifier changes during identification
- **THEN** getkbd SHALL cancel automatic selection and instruct the user to select
  the KVM hub manually

#### Scenario: No hub changes during identification

- **WHEN** the user changes the monitor input but no qualifying hub changes
- **THEN** getkbd SHALL report that no detectable USB signal was found and SHALL
  offer manual hub selection

### Requirement: Refresh local device conditions from system events

The system SHALL observe local Bluetooth, display, USB, sleep, and wake events
without requiring a peer service or network connection.

#### Scenario: Unrelated Bluetooth device changes

- **WHEN** a Bluetooth device other than the selected keyboard connects or
  disconnects
- **THEN** getkbd SHALL not change the selected keyboard state

#### Scenario: Device list refresh is requested

- **WHEN** the user chooses Refresh device lists
- **THEN** getkbd SHALL reload the current local keyboard, display, and USB hub
  choices and conditions
