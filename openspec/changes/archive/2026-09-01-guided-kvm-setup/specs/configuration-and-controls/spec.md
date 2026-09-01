# configuration-and-controls Specification

## MODIFIED Requirements

### Requirement: Guide incomplete configuration through onboarding

The system SHALL open a guided setup when a keyboard is not selected or when the
selected automatic source lacks the device conditions it requires. The guided
setup SHALL describe switching choices using the user's physical desk action.

#### Scenario: No keyboard is selected

- **WHEN** getkbd launches without a selected keyboard
- **THEN** getkbd SHALL show guided setup with a clear instruction to select or
  pair the shared keyboard

#### Scenario: Monitor automation lacks a display

- **WHEN** monitor automation is selected without a selected display
- **THEN** guided setup SHALL identify the missing external display as the next
  required step

#### Scenario: KVM automation lacks a condition

- **WHEN** monitor-input automation is selected without either a selected display
  or selected USB hub
- **THEN** guided setup SHALL identify the missing condition and SHALL offer hub
  detection before requiring manual hub selection

#### Scenario: Manual-only mode has only a keyboard

- **WHEN** manual-only mode is selected with a keyboard but no display or USB
  hub
- **THEN** the missing automatic devices SHALL not require onboarding

#### Scenario: User chooses cable swapping

- **WHEN** the user selects `Unplug and reconnect the display cable`
- **THEN** setup SHALL explain that getkbd watches the selected display appear on
  one Mac and disappear from the other

#### Scenario: User chooses monitor-input switching

- **WHEN** the user selects `Both Macs stay connected and I change the monitor
  input`
- **THEN** setup SHALL explain that it will detect the USB connection that
  follows the selected input and SHALL offer paired-Mac verification

### Requirement: Provide live menu-bar status and manual actions

The system SHALL provide a menu-bar interface showing the selected-device state,
ownership reason, automatic conditions, peer verification state when configured,
display-handoff state when active, errors, and explicit keyboard actions.

#### Scenario: Keyboard is configured

- **WHEN** the menu is opened with a selected keyboard
- **THEN** it SHALL show the keyboard connection state, ownership reason, desk
  monitor condition, hub condition, switching method, and any current error

#### Scenario: KVM setup is unverified

- **WHEN** monitor-input switching is selected but peer verification or the KVM
  test has not passed
- **THEN** the menu SHALL show `Setup not verified` and offer access to setup
  without hiding manual keyboard actions

#### Scenario: Display layout is being handed off

- **WHEN** getkbd is preparing, protecting, restoring, or recovering the display
  layout during a keyboard handoff
- **THEN** the menu SHALL show the current display-handoff phase or attention
  state

#### Scenario: Keyboard is not configured

- **WHEN** no keyboard is selected
- **THEN** the menu and status tooltip SHALL identify the keyboard as not
  configured and SHALL offer a path to guided setup

#### Scenario: User claims or releases manually

- **WHEN** the user chooses Get Keyboard, Release Keyboard, or the configured
  global shortcut
- **THEN** getkbd SHALL request the corresponding manual ownership action

#### Scenario: Bluetooth operation is busy

- **WHEN** a claim or release is in progress
- **THEN** the manual menu actions SHALL be disabled until the operation is no
  longer busy while the current operation remains visible

## ADDED Requirements

### Requirement: Show actionable setup readiness

The guided setup SHALL present a single readiness state, the next unmet
requirement, and contextual recovery actions for device, peer, hub, keyboard,
and display-layout problems.

#### Scenario: All selected requirements pass

- **WHEN** the selected keyboard and display conditions are valid and the chosen
  switching path is verified or intentionally local-only
- **THEN** setup SHALL show `Ready on this Mac` and summarize how switching will
  work

#### Scenario: A requirement is missing

- **WHEN** any required setup condition is absent
- **THEN** setup SHALL show `Needs attention`, identify the next step, and place
  its recovery action near that step

#### Scenario: Login-item update fails

- **WHEN** macOS rejects the login-item update
- **THEN** the UI SHALL show the actual registration state or a specific action,
  such as using the packaged app or approving it in System Settings
