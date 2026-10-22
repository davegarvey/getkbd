## 1. Settings model

- [x] 1.1 Add monitor connections (display identifier, hub group, learned inputs) to the settings, derive the overall hub group from them, and migrate and write the legacy keys
- [x] 1.2 Discard connections when a different monitor is selected

## 2. Detection

- [x] 2.1 Recognise the selected monitor by any known identity, or by a unique name match, and report the current identity
- [x] 2.2 Save a newly recognised identity as a connection and use the current identity for primary-display sync, DDC and input learning
- [x] 2.3 Learn a new connection's hub group in the background from the next switch away and back, abandoning half-finished switches after two minutes
- [x] 2.4 Skip input learning for a connection with no hub group

## 3. Interface

- [x] 3.1 Show the selected monitor once in the Settings picker and base the offline note on recognition
- [x] 3.2 Save hubs from monitor-switch setup for the current connection; show the unlearned state in the monitor-switching row
- [x] 3.3 Add the menu state for a connection still being learned

## 4. Verification

- [x] 4.1 Add checks for recognition, settings migration, per-connection inputs, the menu state and background hub learning; update XCTest sources
- [ ] 4.2 Install on this Mac, confirm the monitor is recognised after the cable swap and that one switch away and back learns the new hubs
