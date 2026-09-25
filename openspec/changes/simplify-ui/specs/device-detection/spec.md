## MODIFIED Requirements

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

## ADDED Requirements

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

## REMOVED Requirements

### Requirement: Identify the selected hub locally

**Reason**: Replaced by "Identify the monitor's hub group locally", which selects
every hub that leaves and returns with a monitor switch instead of requiring
exactly one changed hub, and removes manual hub selection.

**Migration**: Existing single-hub selections continue to work as a group of one.
Run monitor-switch setup again to record the full group.
