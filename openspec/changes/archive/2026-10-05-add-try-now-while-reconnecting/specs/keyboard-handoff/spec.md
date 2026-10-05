## MODIFIED Requirements

### Requirement: Reconcile ownership changes and retry automatic operations

The system SHALL converge toward the latest desired keyboard state after an
in-flight operation and SHALL retry eligible automatic failures a limited number
of times. The system SHALL let the user restart a claim immediately while one is
in progress or awaiting retry.

#### Scenario: Sensor reverses during a claim

- **WHEN** the USB hub disappears while a claim is in flight
- **THEN** getkbd SHALL finish the current operation and then reconcile toward the
  disconnected state

#### Scenario: Automatic operation fails temporarily

- **WHEN** an automatic claim or release fails while its triggering condition
  remains valid
- **THEN** getkbd SHALL retry after the next scheduled delay, up to six claim
  retries with delays increasing from 5 to 60 seconds or two release retries one
  second apart, and SHALL stop retrying when the condition no longer applies

#### Scenario: Manual action overrides an automatic intent

- **WHEN** Get Keyboard or Release Keyboard is selected
- **THEN** getkbd SHALL replace the current automatic target with the requested
  manual target until a subsequent local sensor transition or restart

#### Scenario: User restarts a claim that is awaiting retry

- **WHEN** the user chooses Try Now while an automatic claim retry is scheduled
- **THEN** getkbd SHALL cancel the scheduled retry, start a claim immediately,
  and SHALL keep the current automatic or manual target

#### Scenario: User restarts a claim that is in progress

- **WHEN** the user chooses Try Now while a claim is waiting for the keyboard to
  pair
- **THEN** getkbd SHALL stop that pairing attempt and start a new claim
  immediately after it stops

#### Scenario: Claim started with Try Now fails

- **WHEN** a claim started with Try Now fails while its automatic triggering
  condition remains valid
- **THEN** getkbd SHALL retry it on the automatic schedule from the first delay
