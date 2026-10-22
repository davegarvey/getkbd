## 1. Settings model

- [x] 1.1 Add monitor connections with learned inputs to the settings, migrate stored inputs, and keep writing the legacy key
- [x] 1.2 Discard connections when a different monitor is selected
- [x] 1.3 Complete a connection's missing input from another connection's pair

## 2. Detection

- [x] 2.1 Recognise the selected monitor by any known identity, or by a unique name match, and report the current identity
- [x] 2.2 Save a newly recognised identity as a connection and use the current identity for primary-display sync, DDC and input learning

## 3. Interface

- [x] 3.1 Show the selected monitor once in the Settings picker and base the offline note on recognition
- [x] 3.2 Use the current connection's inputs for the menu's monitor action

## 4. Verification

- [x] 4.1 Add checks for recognition, settings migration, per-connection inputs and pair completion; update XCTest sources
- [x] 4.2 Install on this Mac and confirm recognition, a single Settings entry and Switch Monitor to Other Mac after the cable swap
