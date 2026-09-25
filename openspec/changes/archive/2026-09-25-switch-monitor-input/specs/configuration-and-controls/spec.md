## MODIFIED Requirements

### Requirement: Persist local application settings

The system SHALL persist the selected keyboard, external display, USB hub group,
main-display preference, launch-at-login preference, and the monitor inputs
learned for the selected display between runs.

#### Scenario: First run has no saved settings

- **WHEN** no valid getkbd settings are stored
- **THEN** getkbd SHALL use unset keyboard, display, and USB hub group
  selections, no learned monitor inputs, an enabled main-display preference, and
  enabled launch at login

#### Scenario: Valid settings are stored

- **WHEN** valid settings are present in local preferences
- **THEN** getkbd SHALL restore them at startup

#### Scenario: Stored settings are incomplete

- **WHEN** older settings omit a current local setting
- **THEN** getkbd SHALL retain the decodable device values, SHALL use the default
  for each missing preference, and SHALL require setup only for missing
  selections

#### Scenario: Settings from an earlier version are stored

- **WHEN** stored settings contain a single selected USB hub or a keyboard
  shortcut
- **THEN** getkbd SHALL treat the single hub as a hub group of one and SHALL
  ignore the shortcut without requiring setup again


### Requirement: Show concise menu-bar status and actions

The system SHALL provide a menu-bar menu containing one line that describes where
the keyboard is, at most one keyboard action appropriate to that state, at most
one monitor action, Settings, and Quit. The menu SHALL not show separate display, USB hub, or setup-readiness
lines, raw error text, or a keyboard shortcut. The menu-bar icon SHALL continue
to reflect the keyboard state.

#### Scenario: Setup is not finished

- **WHEN** the keyboard, display, or hub group is not selected
- **THEN** the menu SHALL state that setup is not finished, SHALL offer Finish
  Setup, and SHALL offer no keyboard action

#### Scenario: Keyboard is connected to this Mac

- **WHEN** setup is complete and the keyboard is connected to this Mac
- **THEN** the menu SHALL state that the keyboard is connected to this Mac and
  SHALL offer Release Keyboard

#### Scenario: Monitor is showing the other Mac

- **WHEN** setup is complete, the selected display is online, no hub in the
  group is present, and the keyboard is not connected to this Mac
- **THEN** the menu SHALL state that the monitor is showing the other Mac and
  SHALL offer no keyboard action

#### Scenario: Monitor is showing this Mac but the keyboard is not connected

- **WHEN** setup is complete, a hub in the group is present, the keyboard is not
  connected, and no operation is in progress or failed
- **THEN** the menu SHALL state that the keyboard is not connected and SHALL offer
  Get Keyboard

#### Scenario: Selected monitor is not connected

- **WHEN** setup is complete, the selected display is offline, and the keyboard
  is not connected to this Mac
- **THEN** the menu SHALL state that the monitor is not connected and SHALL offer
  Get Keyboard

#### Scenario: Operation is in progress

- **WHEN** a claim or release is in progress
- **THEN** the menu SHALL state that the keyboard is connecting or releasing and
  SHALL offer no keyboard action

#### Scenario: Operation failed

- **WHEN** the most recent claim or release failed
- **THEN** the menu SHALL state that getkbd could not connect or release the
  keyboard and SHALL offer Try Again, which repeats the failed operation

#### Scenario: User claims or releases manually

- **WHEN** the user chooses Get Keyboard or Release Keyboard
- **THEN** getkbd SHALL request the corresponding manual ownership action

#### Scenario: Monitor can be switched to the other Mac

- **WHEN** setup is complete, no operation is in progress, a hub in the group is
  present, the monitor's input control is available, and the other Mac's input
  is known
- **THEN** the menu SHALL offer Switch Monitor to Other Mac

#### Scenario: Monitor can be switched to this Mac

- **WHEN** setup is complete, no operation is in progress, the selected display
  is online, no hub in the group is present, the monitor's input control is
  available, and this Mac's input is known
- **THEN** the menu SHALL offer Switch Monitor to This Mac

#### Scenario: Monitor cannot be switched

- **WHEN** the monitor's input control is unavailable, the needed input is not
  known, the selected display is offline, setup is incomplete, or an operation
  is in progress
- **THEN** the menu SHALL offer no monitor action
