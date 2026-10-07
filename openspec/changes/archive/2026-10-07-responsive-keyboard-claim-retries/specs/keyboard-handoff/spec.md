## MODIFIED Requirements

### Requirement: Reconcile ownership changes and retry automatic operations
The system SHALL converge toward the latest desired keyboard state after an
in-flight operation and SHALL retry eligible automatic failures a bounded number
of times. Automatic claim retries SHALL run sequentially and SHALL give the
keyboard a rapid recovery period before backing off. The system SHALL let the
user restart a claim immediately while one is in progress or awaiting retry.

#### Scenario: Sensor reverses during a claim
- **WHEN** the USB hub disappears while a claim is in flight
- **THEN** getkbd SHALL finish the current operation and then reconcile toward the
  disconnected state

#### Scenario: Automatic claim retries during the fast recovery window
- **WHEN** an automatic claim fails while the monitor and selected USB hub
  conditions remain eligible
- **THEN** getkbd SHALL start the next claim as soon as the failed claim finishes
  for the first two minutes of the retry cycle, SHALL keep no more than one claim
  in flight, and SHALL start no more than one claim in any five-second interval

#### Scenario: Automatic claim backs off after the fast recovery window
- **WHEN** automatic claims continue to fail after the first two minutes of the
  retry cycle while the monitor and selected USB hub conditions remain eligible
- **THEN** getkbd SHALL retry after waits of 15 seconds, 30 seconds, and 60
  seconds, in that order, and SHALL stop after the final retry

#### Scenario: Automatic release fails temporarily
- **WHEN** an automatic release fails while its triggering condition remains
  valid
- **THEN** getkbd SHALL retry the release twice, one second apart, and SHALL stop
  retrying when the condition no longer applies

#### Scenario: Automatic operation fails temporarily
- **WHEN** an automatic claim or release fails while its triggering condition
  remains valid
- **THEN** getkbd SHALL retry claims using the fast recovery window and bounded
  backoff, SHALL retry releases twice one second apart, and SHALL stop retrying
  when the triggering condition no longer applies

#### Scenario: Ownership condition becomes ineligible during retry
- **WHEN** the selected display or USB hub condition becomes ineligible while an
  automatic claim is awaiting retry
- **THEN** getkbd SHALL cancel the pending claim retry and SHALL reconcile toward
  the disconnected state

#### Scenario: Local signal becomes eligible again after retry failures
- **WHEN** a monitor or selected USB hub transition makes the automatic claim
  condition eligible again after a failed or exhausted retry cycle
- **THEN** getkbd SHALL reset the retry cycle and begin a new automatic claim
  without waiting for the previous cycle's backoff

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
- **THEN** getkbd SHALL resume the automatic retry cycle from its fast recovery
  window
