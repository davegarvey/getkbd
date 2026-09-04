## 1. Display Reconciliation

- [x] 1.1 Track the current primary display separately from active-display membership and trigger the existing idempotent synchronization when the primary changes; verify a primary-only display reconfiguration is corrected by `DisplayPrimaryTests`.
- [x] 1.2 Change wake release from immediate synchronization to a forced, debounced evaluation while preserving sleep suppression; verify wake correction occurs after the display state settles and does not create a repeated transaction.

## 2. Wake Signal Ordering

- [x] 2.1 Add a current IOKit USB-hub rescan that rebuilds the connected hub map and publishes one fresh stable presence result; verify the project builds and existing hub notification behavior remains debounced.
- [x] 2.2 Refresh the USB hub while display synchronization is suppressed, feed the refreshed signal before releasing the display gate, and pass the same signal to keyboard ownership; verify stale wake state cannot select the wrong primary display or keyboard target.

## 3. Diagnostics And Validation

- [x] 3.1 Include the selected primary target and hub condition in primary-display success/failure logging; verify logs distinguish a WindowServer restore from a getkbd transaction.
- [ ] 3.2 Add regression coverage for hub-absent wake, hub-present wake, display-only primary restoration, clamshell behavior, and display-configuration failure independence; verify `swift test` passes.
- [ ] 3.3 Run `swift build`, `swift test`, `bash scripts/run-checks.sh`, and the manual two-display sleep/wake validation; verify both hub directions, lid-open/lid-closed behavior, unchanged modes/arrangement, and correct primary-display logs.
