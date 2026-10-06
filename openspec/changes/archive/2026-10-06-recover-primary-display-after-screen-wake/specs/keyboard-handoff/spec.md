## MODIFIED Requirements

### Requirement: Preserve safe behavior across sleep and restart

The system SHALL release the keyboard before sleep and re-evaluate local
conditions after wake or application restart. When the selected display and
signals are available, this re-evaluation SHALL also synchronize the preferred
primary display without changing display modes, enablement, mirroring, or relative
arrangement. After wake, getkbd SHALL defer primary-display decisions until the
display state has settled and SHALL use the latest stable local signals rather
than making a decision from stale cached wake state. Display-only sleep SHALL
suspend primary-display changes without itself releasing the keyboard. Display-only
wake SHALL refresh USB state and force primary-display reconciliation after
the display state settles, even if the active display set and hub signal are unchanged.

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

#### Scenario: Screens wake while the monitor belongs to the other Mac

- **WHEN** screens wake without a system wake, the selected monitor is online,
  the hub group is absent, the built-in display is active, and main-display switching is enabled
- **THEN** getkbd SHALL make the built-in display primary after display state settles
  without requiring a new USB transition or moving windows directly

#### Scenario: Screens wake while this Mac has the monitor

- **WHEN** screens wake without a system wake and the selected monitor and hub group
  are present with main-display switching enabled
- **THEN** getkbd SHALL make the selected external display primary after display state settles

#### Scenario: Screen sleep preserves keyboard ownership

- **WHEN** only the screens sleep or wake and the USB ownership signal is unchanged
- **THEN** getkbd SHALL not reset keyboard ownership or manual intent solely because
  of that screen event and SHALL defer primary-display changes while the screens sleep

