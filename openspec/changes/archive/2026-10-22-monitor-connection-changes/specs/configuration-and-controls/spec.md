## MODIFIED Requirements

### Requirement: Persist local application settings

The system SHALL persist the selected keyboard, external display, USB hub group,
the known connections of that display with each connection's learned monitor
inputs, main-display preference, and launch-at-login preference between
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

- **WHEN** stored settings contain learned inputs but no monitor connections
- **THEN** getkbd SHALL treat them as the inputs of a single connection of the
  selected display

#### Scenario: An earlier version reads current settings

- **WHEN** an earlier version of getkbd reads settings written by this version
- **THEN** it SHALL find the hub group and the inputs learned for the originally
  selected display

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
  save the detected hub group when the switch completes

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
- **THEN** getkbd SHALL discard the previous monitor's connections and learned
  inputs
