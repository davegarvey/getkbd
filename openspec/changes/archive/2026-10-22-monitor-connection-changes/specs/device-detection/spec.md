## MODIFIED Requirements

### Requirement: Detect the configured external display while physically online

The system SHALL determine whether the configured display is online through local
CoreGraphics display services, including when it has been temporarily disabled
from the active desktop. Built-in displays SHALL be excluded from the selectable
desk-display list. The configured display SHALL be recognised under any display
identity it has been seen with, because macOS gives a monitor a different
identity for each cable or input it is connected through.

#### Scenario: External display is online

- **WHEN** the configured external display is present in the online display list
- **THEN** the display condition SHALL be present and getkbd SHALL notify the
  ownership controller

#### Scenario: Configured display is physically removed

- **WHEN** the configured external display is no longer online
- **THEN** the display condition SHALL be absent and getkbd SHALL notify the
  ownership controller

#### Scenario: Display changes settle

- **WHEN** macOS emits screen or display-reconfiguration events in quick
  succession
- **THEN** getkbd SHALL debounce evaluation using the configured interval, which
  defaults to 1.5 seconds, before publishing a changed physical condition

#### Scenario: Monitor is connected through a different cable or input

- **WHEN** no known identity of the configured display is online and exactly one
  online external display has the configured display's name
- **THEN** getkbd SHALL treat that display as the configured display and SHALL
  remember its identity as another connection of the same monitor

#### Scenario: Several displays share the monitor's name

- **WHEN** no known identity of the configured display is online and more than
  one online external display has its name
- **THEN** getkbd SHALL treat the configured display as absent
