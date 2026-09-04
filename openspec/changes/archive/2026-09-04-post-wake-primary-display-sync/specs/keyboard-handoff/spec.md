## MODIFIED Requirements

### Requirement: Preserve display configuration during handoff

During keyboard handoff, getkbd SHALL preserve display enablement, mirroring,
display modes, and the relative arrangement of displays. For configured KVM
automation, getkbd SHALL use the stable selected USB hub signal to choose the
preferred primary display: the selected external display when the hub is present,
or the active built-in display when the hub is absent. getkbd SHALL treat a
primary-display change reported by display reconfiguration, including wake
restoration, as a reconciliation trigger even when the set of active displays is
unchanged. getkbd SHALL not enumerate, move, or persist application windows;
macOS SHALL remain responsible for normal window relocation resulting from a
primary-display change.

#### Scenario: USB hub changes while the display remains online

- **WHEN** the selected USB hub appears or disappears while the selected display
  remains online
- **THEN** getkbd SHALL synchronize the preferred primary display according to the
  stable hub condition, SHALL proceed with the existing keyboard ownership
  behavior, and SHALL leave display enablement, mirroring, modes, and relative
  arrangement unchanged

#### Scenario: USB hub disappears while the built-in display is active

- **WHEN** the selected USB hub becomes stably absent while the selected display
  remains online and the built-in display is active
- **THEN** getkbd SHALL make the built-in display primary, SHALL proceed with the
  existing keyboard ownership behavior, and SHALL leave display enablement,
  mirroring, modes, and relative arrangement unchanged

#### Scenario: USB hub disappears during clamshell use

- **WHEN** the selected USB hub becomes stably absent while the selected display
  remains online and the built-in display is inactive
- **THEN** getkbd SHALL not attempt to make the built-in display primary and SHALL
  leave the active external display configuration unchanged

#### Scenario: User manually releases the keyboard

- **WHEN** the user chooses Release Keyboard
- **THEN** getkbd SHALL release the keyboard without changing the preferred primary
  display solely because of the manual action

#### Scenario: Closed-lid active use

- **WHEN** the Mac has no active built-in display but the selected external display
  and USB hub are present
- **THEN** getkbd SHALL allow the external display to remain enabled and primary,
  SHALL not require mirroring, and SHALL not attempt to activate the built-in
  display

#### Scenario: Selected display is offline

- **WHEN** the selected display is not online
- **THEN** getkbd SHALL not attempt display configuration and SHALL not
  automatically claim the keyboard

#### Scenario: Primary-display configuration fails

- **WHEN** macOS rejects or cannot verify a requested primary-display change
- **THEN** getkbd SHALL leave keyboard claim or release behavior independent of
  that failure and SHALL not fail an otherwise eligible keyboard handoff because
  of display-role configuration

#### Scenario: Application-scoped display role ends

- **WHEN** getkbd terminates after applying a primary-display change
- **THEN** getkbd SHALL not persist that primary-display change as permanent
  display configuration

#### Scenario: macOS restores a different primary display

- **WHEN** display reconfiguration, including wake restoration, makes a different
  active display primary while the selected display remains online
- **THEN** getkbd SHALL wait for the display state to settle, evaluate the current
  stable hub condition, and synchronize the preferred primary display without
  waiting for another USB-hub transition or changing display enablement,
  mirroring, modes, or relative arrangement

### Requirement: Preserve safe behavior across sleep and restart

The system SHALL release the keyboard before sleep and re-evaluate local
conditions after wake or application restart. When the selected display and
signals are available, this re-evaluation SHALL also synchronize the preferred
primary display without changing display modes, enablement, mirroring, or relative
arrangement. After wake, getkbd SHALL defer primary-display decisions until the
display state has settled and SHALL use the latest stable local signals rather
than making a decision from stale cached wake state.

#### Scenario: Mac prepares to sleep

- **WHEN** the Mac is preparing to sleep
- **THEN** getkbd SHALL release the selected keyboard, cancel pending automatic
  claims, and SHALL not attempt a primary-display change during sleep preparation

#### Scenario: Mac wakes

- **WHEN** the Mac wakes
- **THEN** getkbd SHALL refresh the keyboard state and USB hub, use the refreshed
  stable hub condition for keyboard ownership, and defer the primary-display
  decision until the display state has settled before updating the preferred
  primary display

#### Scenario: Application starts or restarts

- **WHEN** getkbd starts with configured display and USB-hub selections
- **THEN** getkbd SHALL evaluate the current local signals and synchronize the
  preferred primary display without waiting for a new USB transition

#### Scenario: Application quits

- **WHEN** getkbd quits
- **THEN** getkbd SHALL not release the keyboard as a quit side effect and SHALL
  not persist an application-scoped primary-display change as permanent display
  configuration
