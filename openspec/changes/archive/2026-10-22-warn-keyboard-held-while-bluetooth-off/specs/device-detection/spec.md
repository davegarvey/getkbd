## MODIFIED Requirements

### Requirement: Observe local Bluetooth availability

The system SHALL check the local Bluetooth controller power state at startup, wake,
and at one-second intervals while running. It SHALL distinguish powered on,
powered off, and unavailable controller states. It SHALL not change the Bluetooth
power state except when the user chooses to turn Bluetooth on.

#### Scenario: Bluetooth is off

- **WHEN** the local Bluetooth controller is powered off
- **THEN** getkbd SHALL show "Bluetooth is off" with a keyboard icon carrying a small warning badge and an action
  to turn Bluetooth on, suppress keyboard actions, and pause automatic attempts
- **AND** monitor switching SHALL remain available under its normal conditions

#### Scenario: Bluetooth is off while the keyboard is still paired here

- **WHEN** the local Bluetooth controller is powered off and the selected keyboard
  is still paired to this Mac
- **THEN** getkbd SHALL show "Bluetooth is off, so the keyboard can’t be released"
  instead of "Bluetooth is off", with the same warning badge and the same action
  to turn Bluetooth on

#### Scenario: Bluetooth becomes available again

- **WHEN** Bluetooth returns to powered on
- **THEN** getkbd SHALL refresh the keyboard state and resume ownership reconciliation
  using the current monitor, USB hub, sleep, and manual intent conditions

#### Scenario: Bluetooth controller is unavailable

- **WHEN** the local Bluetooth controller is absent or uninitialized
- **THEN** getkbd SHALL show "Bluetooth is unavailable" and pause keyboard operations

#### Scenario: User enables Bluetooth from the menu

- **WHEN** the user chooses "Turn Bluetooth On"
- **THEN** getkbd SHALL request power on and show "Turning Bluetooth on…" without
  another activation action while awaiting confirmation for up to ten seconds
- **AND** success SHALL require observing the controller powered on
- **AND** a missing power API or failed activation SHALL show "Couldn’t turn Bluetooth on"
  with "Open Bluetooth Settings…" as the fallback
