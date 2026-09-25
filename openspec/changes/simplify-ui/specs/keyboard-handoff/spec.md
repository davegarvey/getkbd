## MODIFIED Requirements

### Requirement: Use the local KVM USB hub as the automatic ownership signal

The system SHALL treat the presence of the selected USB hub group as the automatic
active-input signal. The selected external display SHALL be a joint safety
condition, not an ownership signal. Automatic claim readiness SHALL require the
Mac to be awake, the selected display to be online, and the hub group to be
present locally.

#### Scenario: KVM signal becomes active

- **WHEN** the selected display is online and the hub group becomes stably
  present locally while the Mac is awake
- **THEN** getkbd SHALL schedule a delayed keyboard claim attributed to the USB hub

#### Scenario: KVM safety signal disappears

- **WHEN** the selected display is offline or the hub group is absent
- **THEN** getkbd SHALL request release of the selected keyboard regardless of any
  manual preference and SHALL leave display configuration unchanged

#### Scenario: Both Macs see the selected hub

- **WHEN** a hub in the group is simultaneously visible to both Macs
- **THEN** each local instance SHALL rely only on its local signal and SHALL not
  claim that a remote ownership lock exists

#### Scenario: Hub presence flaps during an input switch

- **WHEN** USB notifications rapidly alternate between present and absent
- **THEN** getkbd SHALL debounce the hub-group condition before changing the
  automatic ownership target

### Requirement: Preserve display configuration during handoff

During keyboard handoff, getkbd SHALL preserve display enablement, mirroring,
display modes, and the relative arrangement of displays. When the main-display
preference is enabled and KVM automation is configured, getkbd SHALL use the
stable hub-group signal to choose the preferred primary display: the selected
external display when the group is present, or the active built-in display when
the group is absent. getkbd SHALL treat a primary-display change reported by
display reconfiguration, including wake restoration, as a reconciliation trigger
even when the set of active displays is unchanged. getkbd SHALL not enumerate,
move, or persist application windows; macOS SHALL remain responsible for normal
window relocation resulting from a primary-display change.

#### Scenario: USB hub changes while the display remains online

- **WHEN** the hub group appears or disappears while the selected display
  remains online and the main-display preference is enabled
- **THEN** getkbd SHALL synchronize the preferred primary display according to the
  stable hub-group condition, SHALL proceed with the existing keyboard ownership
  behavior, and SHALL leave display enablement, mirroring, modes, and relative
  arrangement unchanged

#### Scenario: USB hub disappears while the built-in display is active

- **WHEN** the hub group becomes stably absent while the selected display
  remains online, the built-in display is active, and the main-display preference
  is enabled
- **THEN** getkbd SHALL make the built-in display primary, SHALL proceed with the
  existing keyboard ownership behavior, and SHALL leave display enablement,
  mirroring, modes, and relative arrangement unchanged

#### Scenario: USB hub disappears during clamshell use

- **WHEN** the hub group becomes stably absent while the selected display
  remains online and the built-in display is inactive
- **THEN** getkbd SHALL not attempt to make the built-in display primary and SHALL
  leave the active external display configuration unchanged

#### Scenario: Main-display preference is disabled

- **WHEN** the main-display preference is disabled
- **THEN** getkbd SHALL not change the primary display for any hub transition,
  wake, startup, or display reconfiguration, SHALL leave the current primary
  display as it is at the moment the preference is disabled, and SHALL continue
  keyboard handoff unchanged

#### Scenario: Main-display preference is enabled

- **WHEN** the user enables the main-display preference while KVM automation is
  configured
- **THEN** getkbd SHALL synchronize the preferred primary display from the current
  stable hub-group condition without waiting for another hub transition

#### Scenario: User manually releases the keyboard

- **WHEN** the user chooses Release Keyboard
- **THEN** getkbd SHALL release the keyboard without changing the preferred primary
  display solely because of the manual action

#### Scenario: Closed-lid active use

- **WHEN** the Mac has no active built-in display but the selected external display
  and hub group are present
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
  active display primary while the selected display remains online and the
  main-display preference is enabled
- **THEN** getkbd SHALL wait for the display state to settle, evaluate the current
  stable hub-group condition, and synchronize the preferred primary display
  without waiting for another USB-hub transition or changing display enablement,
  mirroring, modes, or relative arrangement
