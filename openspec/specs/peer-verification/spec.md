# peer-verification Specification

## Purpose

Allow two explicitly paired local getkbd instances to verify monitor-input
switching and report trustworthy setup and handoff status without becoming a
runtime ownership dependency.

## Requirements

### Requirement: Explicitly pair the other getkbd Mac

The system SHALL let a user discover a nearby getkbd instance, see its Mac name,
and explicitly confirm a matching short code on both Macs before treating the
instances as paired.

#### Scenario: Other Mac is discovered

- **WHEN** another getkbd instance advertises itself on the local connection
- **THEN** the setup UI SHALL show that Mac as an available `Other Mac` without
  exposing a raw address as the primary identity

#### Scenario: Pairing is confirmed

- **WHEN** both getkbd instances display the same short confirmation code and the
  user confirms it on both Macs
- **THEN** each instance SHALL persist the paired peer identity and show the peer
  as available for verification

#### Scenario: Pairing is not confirmed

- **WHEN** the codes do not match or the user cancels confirmation
- **THEN** the instances SHALL not exchange setup state and SHALL remain usable
  for local detection and manual switching

#### Scenario: Paired Mac becomes unavailable

- **WHEN** a previously paired Mac is asleep, unreachable, or getkbd is not
  running
- **THEN** the local UI SHALL show the peer as unavailable and SHALL not claim
  that peer verification is current

### Requirement: Exchange verification state without remote ownership control

The system SHALL exchange only the peer state needed for setup verification,
including a stable instance identity, selected-device readiness, current hub
observations, keyboard state, and verification session state.

#### Scenario: Peer status is received

- **WHEN** a paired Mac sends current setup or handoff status
- **THEN** the local UI SHALL update the `Other Mac` status and SHALL not alter
  local keyboard ownership solely because of that message

#### Scenario: Peer connection is unavailable during ordinary use

- **WHEN** the peer connection is unavailable after setup
- **THEN** local monitor, USB-hub, Bluetooth, sleep, and manual behavior SHALL
  continue without waiting for the peer

#### Scenario: Unexpected peer message is received

- **WHEN** a message has an unsupported version, invalid data, or an unknown
  session identifier
- **THEN** getkbd SHALL ignore it, keep local behavior running, and mark peer
  verification as unavailable or stale

### Requirement: Verify a complementary USB-hub transition

The system SHALL correlate hub snapshots from both paired Macs during a named
verification session and SHALL report a verified transition only when one stable
hub descriptor disappears from one Mac while appearing on the other without
competing changes.

#### Scenario: Hub follows the monitor input

- **WHEN** the user changes the monitor input and the same hub disappears from one
  Mac and appears on the other
- **THEN** the verification result SHALL identify that hub as following the
  monitor input

#### Scenario: Both Macs see the hub

- **WHEN** the same selected hub remains visible on both Macs after the input
  switch
- **THEN** the result SHALL be marked unsafe and the setup SHALL not be reported
  as verified

#### Scenario: No complementary transition occurs

- **WHEN** the input changes but no hub appears or disappears on either Mac
- **THEN** the UI SHALL explain that the switch did not expose a detectable USB
  signal and SHALL offer manual switching or local hub selection

#### Scenario: Several hubs change

- **WHEN** more than one hub changes during the verification session
- **THEN** the result SHALL be marked ambiguous and the UI SHALL offer manual
  selection rather than choosing a hub automatically

### Requirement: Verify an end-to-end KVM handoff

The system SHALL provide a user-driven KVM test that observes the monitor-input
change, local keyboard release, remote keyboard claim, and display-layout
protection/restoration in both directions where both Macs are available.

#### Scenario: First test direction succeeds

- **WHEN** the user changes the monitor input to the other Mac while both paired
  getkbd instances are ready
- **THEN** the test SHALL show the local release and remote claim as completed
  before asking the user to switch back

#### Scenario: Both directions succeed

- **WHEN** the user switches to the other input and then switches back, with both
  handoffs completing successfully
- **THEN** the KVM setup SHALL be marked verified and ready

#### Scenario: User skips the test

- **WHEN** the user continues without completing the KVM test
- **THEN** the configuration SHALL remain usable but SHALL be marked unverified
  in setup and status UI

#### Scenario: Handoff test fails

- **WHEN** the hub transition, keyboard operation, peer status, or display
  restoration does not complete
- **THEN** the UI SHALL identify the failed stage and provide retry or fallback
  guidance
