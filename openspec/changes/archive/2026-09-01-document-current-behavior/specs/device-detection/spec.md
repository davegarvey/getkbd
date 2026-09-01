## Purpose

Define how getkbd discovers paired keyboards and identifies the selected
external display and physical KVM USB hub on the local Mac.

## ADDED Requirements

### Requirement: Discover paired Bluetooth keyboards

The system SHALL list locally paired Bluetooth devices that identify as a
keyboard by Bluetooth class or by a name containing "keyboard".

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

### Requirement: Detect the configured external display

The system SHALL determine whether the configured display is currently present
among the local macOS screens and SHALL exclude built-in displays from the
selectable desk-monitor list.

#### Scenario: External display is selected

- **WHEN** the configured external display appears in the current screen list
- **THEN** the display condition SHALL be present and getkbd SHALL notify the
  ownership controller of a monitor connection

#### Scenario: Configured display disappears

- **WHEN** the configured external display is no longer in the current screen
  list
- **THEN** the display condition SHALL be absent and getkbd SHALL notify the
  ownership controller of a monitor disconnection

#### Scenario: Display changes settle

- **WHEN** macOS emits screen or display-reconfiguration events in quick
  succession
- **THEN** getkbd SHALL debounce evaluation using the configured interval,
  which defaults to 1.5 seconds, before publishing a changed condition

#### Scenario: Built-in display is listed

- **WHEN** getkbd populates the desk-monitor selector
- **THEN** built-in displays SHALL not be offered as desk-monitor choices

### Requirement: Detect physical USB hubs for KVM switching

The system SHALL list connected USB host devices that expose USB device class 9
and SHALL track presence of the selected hub using a stable descriptor.

#### Scenario: USB hub is connected

- **WHEN** a qualifying physical USB hub is connected
- **THEN** getkbd SHALL expose its name, manufacturer, vendor ID, product ID, and
  identifier in the settings list and update its selected-presence condition

#### Scenario: Non-hub USB device is connected

- **WHEN** a USB device does not expose device class 9 or lacks vendor/product
  identifiers
- **THEN** getkbd SHALL omit it from the KVM hub list

#### Scenario: Selected hub is removed

- **WHEN** the selected USB hub terminates
- **THEN** getkbd SHALL mark it absent, refresh the hub list, and notify KVM
  ownership logic

#### Scenario: Hub has no serial number

- **WHEN** a qualifying hub has no serial number
- **THEN** its identifier SHALL be derived from its vendor, product, name, and
  manufacturer values

### Requirement: Refresh device conditions from local system events

The system SHALL observe Bluetooth connection changes for the selected keyboard,
display changes, USB hub arrivals, USB hub removals, sleep, and wake without
requiring a remote service.

#### Scenario: Unrelated Bluetooth device changes

- **WHEN** a Bluetooth device other than the selected keyboard connects or
  disconnects
- **THEN** getkbd SHALL not change the selected keyboard state because of that
  event

#### Scenario: Device list refresh is requested

- **WHEN** the user chooses Refresh Keyboard, Monitor, and USB Hub Lists
- **THEN** getkbd SHALL reload the current local keyboard, display, and USB hub
  choices and presence conditions

#### Scenario: Selected hub is identified interactively

- **WHEN** the user starts KVM hub identification and exactly one hub identifier
  changes
- **THEN** getkbd SHALL select that changed hub and report the detected hub

#### Scenario: Several hubs change during identification

- **WHEN** more than one hub identifier changes during identification
- **THEN** getkbd SHALL cancel automatic identification and instruct the user to
  select the KVM hub manually
