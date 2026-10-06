## MODIFIED Requirements

### Requirement: Show concise menu-bar status and actions

The system SHALL provide a menu-bar menu containing one line that describes where
the keyboard is, at most one keyboard action appropriate to that state, at most
one monitor action, Settings, and Quit. The menu SHALL not show separate display, USB hub, or setup-readiness
lines, raw error text, or a keyboard shortcut. The menu-bar icon SHALL continue
to reflect the keyboard state.

#### Scenario: Menu-bar icon while getkbd is working

- **WHEN** a claim or release is in progress, or an automatic claim is being
  retried
- **THEN** the menu-bar icon SHALL show a keyboard with an ellipsis badge, distinct
  from the filled keyboard shown when connected and the outline keyboard shown
  when not connected

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
  connected, and no operation is in progress, failed, or awaiting retry
- **THEN** the menu SHALL state that the keyboard is not connected and SHALL offer
  Get Keyboard

#### Scenario: Selected monitor is not connected

- **WHEN** setup is complete, the selected display is offline, and the keyboard
  is not connected to this Mac
- **THEN** the menu SHALL state that the monitor is not connected and SHALL offer
  Get Keyboard

#### Scenario: Operation is in progress

- **WHEN** a release is in progress, or a claim is in progress and no earlier
  automatic claim in the current retry sequence has failed
- **THEN** the menu SHALL state that the keyboard is connecting or releasing,
  SHALL offer Try Now while connecting, and SHALL offer no keyboard action while
  releasing

#### Scenario: Automatic claim is being retried

- **WHEN** an automatic claim has failed and getkbd is either waiting to retry it
  or retrying it
- **THEN** the menu SHALL state that the keyboard is not responding and SHALL
  offer Try Now

#### Scenario: Operation failed

- **WHEN** the most recent claim or release failed and no automatic retry is
  pending
- **THEN** the menu SHALL state that getkbd could not connect or release the
  keyboard and SHALL offer Try Again, which repeats the failed operation

#### Scenario: User claims or releases manually

- **WHEN** the user chooses Get Keyboard or Release Keyboard
- **THEN** getkbd SHALL request the corresponding manual ownership action

#### Scenario: User chooses Try Now

- **WHEN** the user chooses Try Now
- **THEN** getkbd SHALL restart the claim immediately

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
