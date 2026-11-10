## ADDED Requirements

### Requirement: Recover from a Bluetooth service restart

The system SHALL detect, using only unprivileged local process information, when
macOS's Bluetooth service has restarted since getkbd started, and SHALL relaunch
getkbd so that keyboard claims use a fresh Bluetooth session. A relaunch SHALL not
claim or release the keyboard by itself and SHALL happen at most once in any
10-minute period. Detections, relaunches and skipped relaunches SHALL be logged.

#### Scenario: Bluetooth service restarts while getkbd is idle

- **WHEN** the Bluetooth service has a different process identity from the one
  recorded at getkbd's start and no keyboard operation is in progress
- **THEN** getkbd SHALL relaunch within one minute, and the new instance SHALL
  evaluate the current local signals as on any start

#### Scenario: Claim is due after a restart

- **WHEN** a keyboard claim is about to start and the Bluetooth service has
  restarted since getkbd started
- **THEN** getkbd SHALL relaunch instead of starting the claim, and the new
  instance SHALL claim according to the current signals

#### Scenario: Release is due after a restart

- **WHEN** a keyboard release is about to start and the Bluetooth service has
  restarted since getkbd started
- **THEN** getkbd SHALL attempt the release first and SHALL relaunch after it
  finishes, so that a pairing is not left behind on this Mac

#### Scenario: Mac is sleeping or preparing to sleep

- **WHEN** a relaunch would be due while the Mac is preparing to sleep or asleep
- **THEN** getkbd SHALL defer the relaunch until after wake

#### Scenario: Operation in progress when a restart is detected

- **WHEN** a restart is detected while a keyboard claim or release is in progress
- **THEN** getkbd SHALL let the operation finish and SHALL relaunch afterwards

#### Scenario: Claims get no answer from Bluetooth

- **WHEN** two consecutive automatic claims end at getkbd's pairing timeout without
  any result from Bluetooth
- **THEN** getkbd SHALL relaunch even if no Bluetooth service restart was detected

#### Scenario: Relaunch limit reached

- **WHEN** a relaunch would be due less than 10 minutes after the previous one
- **THEN** getkbd SHALL not relaunch, SHALL log that the relaunch was skipped, and
  SHALL continue its normal claim and retry behavior

#### Scenario: getkbd is not running from an app bundle

- **WHEN** a relaunch would be due and getkbd cannot identify an application bundle
  to start again
- **THEN** getkbd SHALL log the detection and SHALL continue without relaunching
