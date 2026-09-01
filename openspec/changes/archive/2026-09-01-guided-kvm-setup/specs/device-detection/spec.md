# device-detection Specification

## MODIFIED Requirements

### Requirement: Detect physical USB hubs for KVM switching

The system SHALL list connected USB host devices that expose USB device class 9,
track presence of the selected hub using a stable descriptor, and support local
or paired verification of a hub transition.

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

#### Scenario: Paired Macs observe a complementary transition

- **WHEN** a paired verification session observes the same stable hub disappear
  from one Mac and appear on the other during the monitor-input change
- **THEN** getkbd SHALL report that hub as the verified input-switch signal

### Requirement: Refresh device conditions from local system events

The system SHALL observe local Bluetooth, display, USB, sleep, and wake events
without requiring a peer service. When a paired peer is available, it SHALL also
exchange the local state needed for verification without replacing local event
handling.

#### Scenario: Unrelated Bluetooth device changes

- **WHEN** a Bluetooth device other than the selected keyboard connects or
  disconnects
- **THEN** getkbd SHALL not change the selected keyboard state because of that
  event

#### Scenario: Device list refresh is requested

- **WHEN** the user chooses Refresh Keyboard, Monitor, and USB Hub Lists
- **THEN** getkbd SHALL reload the current local keyboard, display, and USB hub
  choices and presence conditions

#### Scenario: Peer is unavailable

- **WHEN** the paired peer cannot be reached while local devices change
- **THEN** local lists and presence conditions SHALL continue to update normally
  and verification SHALL be marked unavailable

#### Scenario: Selected hub is identified interactively

- **WHEN** the user starts KVM hub identification and exactly one hub identifier
  changes
- **THEN** getkbd SHALL return that changed hub as a local candidate even when
  peer verification is unavailable

#### Scenario: Several hubs change during identification

- **WHEN** more than one hub identifier changes during identification
- **THEN** getkbd SHALL cancel automatic identification and instruct the user to
  select the KVM hub manually

## ADDED Requirements

### Requirement: Identify the selected hub interactively

The system SHALL support local hub identification and SHALL use paired before and
after observations to verify the result when both Macs are available.

#### Scenario: Local identification finds exactly one changed hub

- **WHEN** the user starts hub identification and exactly one local hub
  identifier changes
- **THEN** getkbd SHALL offer that changed hub as the local candidate

#### Scenario: Paired identification confirms one hub

- **WHEN** exactly one stable hub disappears from one paired Mac and appears on
  the other during the same detection session
- **THEN** getkbd SHALL select or offer that hub and report the transition as
  verified

#### Scenario: Several hubs change during identification

- **WHEN** more than one hub identifier changes during identification
- **THEN** getkbd SHALL cancel automatic selection and instruct the user to
  select the KVM hub manually

#### Scenario: No hub changes during identification

- **WHEN** the user changes the monitor input but no qualifying hub changes on
  either Mac
- **THEN** getkbd SHALL report that no detectable USB signal was found and SHALL
  offer manual switching or manual hub selection
