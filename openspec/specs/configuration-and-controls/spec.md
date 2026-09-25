# configuration-and-controls Specification

## Purpose

Define getkbd's local configuration, menu-bar controls, settings workflow,
shortcut behavior, and login startup experience.

## Requirements

### Requirement: Persist local application settings

The system SHALL persist the selected keyboard, external display, USB hub group,
main-display preference, and launch-at-login preference between runs.

#### Scenario: First run has no saved settings

- **WHEN** no valid getkbd settings are stored
- **THEN** getkbd SHALL use unset keyboard, display, and USB hub group
  selections, an enabled main-display preference, and enabled launch at login

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

### Requirement: Show actionable setup readiness

The settings window SHALL show the next unmet setup step prominently until setup
is complete, and SHALL then reduce monitor-switch setup to a single form row.

#### Scenario: A requirement is missing

- **WHEN** any required setup selection is absent
- **THEN** settings SHALL show the next step as the most prominent element of the
  window

#### Scenario: All selected requirements pass

- **WHEN** the keyboard, display, and hub group are selected
- **THEN** settings SHALL show monitor switching as set up, with an option to set
  it up again, and SHALL show no readiness banner

### Requirement: Support optional launch at login

The system SHALL expose a launch-at-login setting through the packaged app's
macOS login-item service.

#### Scenario: Packaged signed app enables login

- **WHEN** the user enables launch at login from a properly packaged and signed
  app
- **THEN** getkbd SHALL register the app as a macOS login item and persist the
  preference

#### Scenario: Login-item registration fails

- **WHEN** macOS rejects a login-item update
- **THEN** getkbd SHALL restore the checkbox to its prior state and show a specific
  recovery message

#### Scenario: Login item needs approval

- **WHEN** macOS reports that the login item requires approval
- **THEN** settings SHALL show a note beside the checkbox with a way to open Login
  Items settings, and SHALL show no login-item status otherwise

### Requirement: Run as a local menu-bar application

The system SHALL run as an accessory menu-bar app, start local observers at launch,
and stop observers on termination.

#### Scenario: Application launches

- **WHEN** getkbd starts
- **THEN** it SHALL initialize local Bluetooth, display, USB hub, sleep, and wake
  monitoring before publishing menu status

#### Scenario: Application quits

- **WHEN** the user quits getkbd
- **THEN** getkbd SHALL leave the display configuration unchanged and SHALL not
  automatically release the keyboard as a quit side effect

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
- **THEN** getkbd SHALL replace the stored hub group with the newly detected group

### Requirement: Show concise menu-bar status and actions

The system SHALL provide a menu-bar menu containing one line that describes where
the keyboard is, at most one keyboard action appropriate to that state, Settings,
and Quit. The menu SHALL not show separate display, USB hub, or setup-readiness
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
