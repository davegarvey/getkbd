# configuration-and-controls Specification

## Purpose

Define getkbd's local configuration, menu-bar controls, settings workflow,
shortcut behavior, and login startup experience.

## Requirements

### Requirement: Persist local application settings

The system SHALL persist the selected keyboard, external display, USB hub,
shortcut, and launch-at-login preference between runs.

#### Scenario: First run has no saved settings

- **WHEN** no valid getkbd settings are stored
- **THEN** getkbd SHALL use unset keyboard, display, and USB hub selections, the
  default Ctrl+Opt+Cmd+K shortcut, and enabled launch at login

#### Scenario: Valid settings are stored

- **WHEN** valid settings are present in local preferences
- **THEN** getkbd SHALL restore them at startup

#### Scenario: Stored settings are incomplete

- **WHEN** older settings omit a current local setting
- **THEN** getkbd SHALL retain the decodable device and shortcut values and SHALL
  require setup only for missing selections

### Requirement: Guide local KVM setup

The settings window SHALL guide the user to select the same paired keyboard and
external monitor on both Macs and to identify the USB hub that follows the monitor
input. Setup SHALL not require the other Mac to be discoverable or connected to a
network.

#### Scenario: A required device is missing

- **WHEN** the keyboard, external display, or USB hub is not selected
- **THEN** guided setup SHALL identify that local device as the next required step

#### Scenario: Selected device is temporarily absent

- **WHEN** a previously selected keyboard, display, or USB hub is not currently
  detected
- **THEN** settings SHALL retain and display the selection as unavailable rather
  than silently replacing it

#### Scenario: User identifies the KVM hub

- **WHEN** the user starts local hub identification and exactly one hub identifier
  changes after the monitor input changes
- **THEN** getkbd SHALL select that hub locally

#### Scenario: Several hubs change during identification

- **WHEN** more than one hub identifier changes during identification
- **THEN** getkbd SHALL cancel automatic selection and instruct the user to select
  the hub manually

### Requirement: Configure local switching devices

The settings window SHALL allow the user to select a paired keyboard, external
display, USB hub, shortcut, and launch-at-login preference.

#### Scenario: Keyboard selection changes

- **WHEN** the user selects a different keyboard
- **THEN** getkbd SHALL ask the ownership controller to release the old keyboard
  before applying the new selection and SHALL restore the old selection if that
  release fails

#### Scenario: Shortcut changes

- **WHEN** the user records a shortcut containing at least one modifier and a key
- **THEN** getkbd SHALL register and persist the new shortcut

### Requirement: Provide live menu-bar status and manual actions

The system SHALL provide a menu-bar interface showing keyboard state, local USB
hub state, physical display state, errors, and explicit keyboard actions.

#### Scenario: Keyboard is configured

- **WHEN** the menu is opened with a selected keyboard
- **THEN** it SHALL show the keyboard state, input signal state, display state, and
  current ownership action

#### Scenario: Keyboard is not configured

- **WHEN** no keyboard is selected
- **THEN** the menu SHALL identify the keyboard as not configured, offer settings,
  and disable manual keyboard actions

#### Scenario: User claims or releases manually

- **WHEN** the user chooses Get Keyboard, Release Keyboard, or the configured
  global shortcut
- **THEN** getkbd SHALL request the corresponding manual ownership action

#### Scenario: Bluetooth operation is busy

- **WHEN** a claim or release is in progress
- **THEN** the manual menu actions SHALL be disabled until the operation is no
  longer busy

### Requirement: Show actionable setup readiness

The guided setup SHALL present a single readiness state and the next unmet local
requirement.

#### Scenario: All selected requirements pass

- **WHEN** the selected keyboard, external display, and USB hub are configured
- **THEN** setup SHALL show Ready to switch and explain that changing the monitor
  input moves the keyboard locally without a network connection

#### Scenario: A requirement is missing

- **WHEN** any required setup selection is absent
- **THEN** setup SHALL show Needs attention and identify the next step

### Requirement: Register and edit the global shortcut

The system SHALL register the configured Carbon global hotkey exclusively and
shall allow the user to record a replacement shortcut containing at least one
modifier and a key.

#### Scenario: Default shortcut registers

- **WHEN** the default shortcut is available at launch
- **THEN** getkbd SHALL register Ctrl+Opt+Cmd+K and invoke Get Keyboard when it
  is pressed

#### Scenario: Shortcut conflicts with another application

- **WHEN** the requested global shortcut cannot be registered
- **THEN** getkbd SHALL keep the previously working shortcut, mark the requested
  shortcut unavailable, and show an explanatory settings message

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

### Requirement: Run as a local menu-bar application

The system SHALL run as an accessory menu-bar app, start local observers at launch,
and stop observers and the global shortcut on termination.

#### Scenario: Application launches

- **WHEN** getkbd starts
- **THEN** it SHALL initialize local Bluetooth, display, USB hub, sleep, wake, and
  shortcut monitoring before publishing menu status

#### Scenario: Application quits

- **WHEN** the user quits getkbd
- **THEN** getkbd SHALL leave the display configuration unchanged and SHALL not
  automatically release the keyboard as a quit side effect
