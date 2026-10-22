## MODIFIED Requirements

### Requirement: Persist local application settings

The system SHALL persist the selected keyboard, external display, the known
connections of that display with each connection's USB hub group and learned
monitor inputs, main-display preference, and launch-at-login preference between
runs.

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

#### Scenario: Settings without monitor connections are stored

- **WHEN** stored settings contain a hub group and learned inputs but no monitor
  connections
- **THEN** getkbd SHALL treat them as a single connection of the selected display

#### Scenario: An earlier version reads current settings

- **WHEN** an earlier version of getkbd reads settings written by this version
- **THEN** it SHALL find the hubs of every connection as its hub group and the
  inputs learned for the originally selected display

### Requirement: Guide local KVM setup

The settings window SHALL guide the user to select the shared keyboard and
external monitor and then to switch the monitor to the other Mac and back so that
getkbd can identify the monitor's USB hub group. Setup SHALL not require the
other Mac to be discoverable or connected to a network, and SHALL not show USB
hub names, identifiers, or a hub list.

#### Scenario: A required device is missing

- **WHEN** the keyboard, external display, or USB hub group is not selected
- **THEN** guided setup SHALL identify that step as the next required step

#### Scenario: Exactly one candidate is available

- **WHEN** no keyboard is selected and exactly one paired keyboard is found, or no
  display is selected and exactly one external display is online
- **THEN** getkbd SHALL select that device automatically and SHALL allow the user
  to change it

#### Scenario: Selected device is temporarily absent

- **WHEN** a previously selected keyboard or display is not currently detected
- **THEN** settings SHALL retain the selection rather than silently replacing it,
  and SHALL show a short note beside the monitor row when the selected display is
  offline. No note SHALL be shown for the keyboard, because releasing it removes
  this Mac's pairing and an unpaired keyboard is the normal state on the Mac the
  monitor is not showing

#### Scenario: Selected monitor is online through another connection

- **WHEN** the selected monitor is online under a different display identity
- **THEN** the monitor list SHALL show the monitor once, selected, with no
  offline note

#### Scenario: User identifies the KVM hub

- **WHEN** the user starts monitor-switch setup
- **THEN** getkbd SHALL instruct the user to switch the monitor to the other Mac
  and then back, SHALL show which part of the switch it is waiting for, and SHALL
  save the detected hub group for the current connection when the switch
  completes

#### Scenario: Several hubs change during identification

- **WHEN** more than one hub leaves and returns during monitor-switch setup
- **THEN** getkbd SHALL save all of those hubs as the hub group without asking the
  user to choose

#### Scenario: Monitor-switch setup is ambiguous

- **WHEN** no USB hub leaves and returns during monitor-switch setup
- **THEN** getkbd SHALL keep any previous hub group and SHALL ask the user to try
  again without offering a manual hub list

#### Scenario: Setup completes

- **WHEN** the keyboard, display, and hub group are all selected for the first
  time
- **THEN** settings SHALL confirm that switching the monitor now moves the
  keyboard and SHALL remind the user to set up getkbd on the other Mac

#### Scenario: A different monitor is selected

- **WHEN** the user selects a different monitor
- **THEN** getkbd SHALL discard the previous monitor's connections, hub groups,
  and learned inputs, and setup SHALL ask for monitor-switch setup again

### Requirement: Change settings in a compact form

The settings window SHALL present a compact form that allows the user to change
the keyboard and external display, repeat monitor-switch setup, change the
main-display preference, and change the launch-at-login preference. It SHALL not
contain manual keyboard controls or explanatory text about internal detection.

#### Scenario: Keyboard selection changes

- **WHEN** the user selects a different keyboard
- **THEN** getkbd SHALL ask the ownership controller to release the old keyboard
  before applying the new selection and SHALL restore the old selection if that
  release fails

#### Scenario: Main-display preference changes

- **WHEN** the user changes "Switch the main display with the monitor"
- **THEN** getkbd SHALL persist the preference and apply it to subsequent
  primary-display decisions

#### Scenario: Monitor switching is set up again

- **WHEN** the user chooses to set up monitor switching again and the new setup
  completes
- **THEN** getkbd SHALL replace the hub group of the current connection with the
  newly detected group and SHALL keep the hub groups of other connections

#### Scenario: Current connection is not set up

- **WHEN** the monitor is online through a connection with no hub group
- **THEN** the monitor-switching row SHALL ask the user to switch the monitor to
  the other Mac and back instead of showing that switching is set up

## ADDED Requirements

### Requirement: Show when a new monitor connection needs a switch

The menu SHALL tell the user when the monitor is connected through a connection
whose hub group has not been learned.

#### Scenario: Monitor connection changed

- **WHEN** setup is complete, the selected monitor is online through a connection
  with no hub group, and the keyboard is not connected to this Mac
- **THEN** the menu SHALL ask the user to switch the monitor to the other Mac and
  back, SHALL offer Get Keyboard, and SHALL offer no monitor action
