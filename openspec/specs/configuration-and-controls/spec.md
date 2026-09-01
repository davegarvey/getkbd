# configuration-and-controls Specification

## Purpose

Define getkbd's persisted configuration, menu-bar controls, settings workflow,
shortcut behavior, onboarding, and login startup experience.

## Requirements

### Requirement: Persist complete application settings

The system SHALL persist the selected keyboard, display, USB hub, automatic
source, behavior flags, shortcut, and launch-at-login preference between runs.

#### Scenario: First run has no saved settings

- **WHEN** no valid getkbd settings are stored
- **THEN** getkbd SHALL use an unset keyboard, display, and USB hub, monitor
  automation, enabled monitor claiming, disabled monitor takeover from manual
  ownership, enabled monitor release, enabled release before sleep, the default
  Ctrl+Opt+Cmd+K shortcut, and enabled launch at login

#### Scenario: Valid settings are stored

- **WHEN** valid settings are present in local preferences
- **THEN** getkbd SHALL restore them at startup

#### Scenario: Stored settings are invalid

- **WHEN** saved settings cannot be decoded
- **THEN** getkbd SHALL discard the invalid value and use all initial defaults

#### Scenario: Legacy KVM setting is loaded

- **WHEN** saved settings use the legacy `kvmInput` automatic-source value
- **THEN** getkbd SHALL interpret it as KVM USB hub automation

### Requirement: Guide incomplete configuration through onboarding

The system SHALL open settings when a keyboard is not selected or when the
selected automatic source lacks the device conditions it requires.

#### Scenario: No keyboard is selected

- **WHEN** getkbd launches without a selected keyboard
- **THEN** getkbd SHALL show the settings window for configuration

#### Scenario: Monitor automation lacks a display

- **WHEN** monitor automation is selected without a selected display
- **THEN** getkbd SHALL show the settings window for configuration

#### Scenario: KVM automation lacks a condition

- **WHEN** KVM USB hub automation is selected without either a selected display
  or selected USB hub
- **THEN** getkbd SHALL show the settings window for configuration

#### Scenario: Manual-only mode has only a keyboard

- **WHEN** manual-only mode is selected with a keyboard but no display or USB
  hub
- **THEN** the missing automatic devices SHALL not require onboarding

### Requirement: Configure devices and switching behavior

The settings window SHALL allow the user to select a paired keyboard, external
display, USB hub, automatic source, monitor behavior, sleep behavior, shortcut,
and launch-at-login preference.

#### Scenario: Selected device is temporarily absent

- **WHEN** a previously selected keyboard, display, or USB hub is not currently
  detected
- **THEN** settings SHALL retain and display the selection as not currently
  available rather than silently replacing it

#### Scenario: Automatic source changes

- **WHEN** the user changes the automatic source or a behavior checkbox
- **THEN** getkbd SHALL persist the change and immediately re-evaluate ownership
  using current device conditions

#### Scenario: Monitor-only options are hidden

- **WHEN** the automatic source is KVM USB hub or manual only
- **THEN** monitor-specific claim, takeover, and disconnect options SHALL be
  hidden while their stored values are retained

#### Scenario: Keyboard selection changes

- **WHEN** the user selects a different keyboard
- **THEN** getkbd SHALL ask the ownership controller to release the old keyboard
  before applying the new selection and SHALL restore the old selection if that
  release fails

### Requirement: Provide live menu-bar status and manual actions

The system SHALL provide a menu-bar interface showing selected-device status,
ownership reason, automatic conditions, errors, and explicit Get Keyboard and
Release Keyboard actions.

#### Scenario: Keyboard is configured

- **WHEN** the menu is opened with a selected keyboard
- **THEN** it SHALL show the keyboard connection state, ownership reason, desk
  monitor condition, KVM hub condition, switching method, and any current error

#### Scenario: Keyboard is not configured

- **WHEN** no keyboard is selected
- **THEN** the menu and status tooltip SHALL identify the keyboard as not
  configured and disable the manual claim and release actions

#### Scenario: User claims or releases manually

- **WHEN** the user chooses Get Keyboard, Release Keyboard, or the configured
  global shortcut
- **THEN** getkbd SHALL request the corresponding manual ownership action

#### Scenario: Bluetooth operation is busy

- **WHEN** a claim or release is in progress
- **THEN** the manual menu actions SHALL be disabled until the operation is no
  longer busy

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
  shortcut unavailable in the menu, and show an explanatory settings message

#### Scenario: User records a shortcut

- **WHEN** the user records a shortcut and presses a key with at least one
  modifier
- **THEN** getkbd SHALL persist that key and modifier combination and register
  it for future Get Keyboard actions

#### Scenario: User cancels shortcut recording

- **WHEN** the user presses Escape while recording a shortcut
- **THEN** getkbd SHALL leave the existing shortcut unchanged

### Requirement: Support optional launch at login

The system SHALL expose a launch-at-login setting through the packaged app's
macOS login-item service.

#### Scenario: Packaged signed app enables login

- **WHEN** the user enables launch at login from a properly packaged and signed
  app
- **THEN** getkbd SHALL register the app as a macOS login item and persist the
  preference

#### Scenario: Login-item registration fails

- **WHEN** macOS rejects a login-item update, including an unsupported or
  improperly packaged app
- **THEN** getkbd SHALL restore the checkbox to its prior state and show a
  message telling the user to use the packaged app bundle

#### Scenario: Launch preference is enabled at startup

- **WHEN** saved settings enable launch at login
- **THEN** getkbd SHALL attempt to register the app during launch without
  preventing the rest of the app from starting

### Requirement: Run as a menu-bar application and stop observers cleanly

The system SHALL run as an accessory menu-bar app, start its local observers at
launch, and stop observers and the global shortcut on termination without
implicitly releasing the keyboard.

#### Scenario: Application launches

- **WHEN** getkbd starts
- **THEN** it SHALL initialize the selected keyboard, display, USB hub, sleep,
  Bluetooth, and shortcut monitoring before publishing its menu status

#### Scenario: Application quits

- **WHEN** the user quits getkbd
- **THEN** getkbd SHALL stop its monitors and shortcut registration and SHALL not
  automatically release the keyboard as a quit side effect
