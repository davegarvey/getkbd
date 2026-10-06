## 1. Screen wake recovery

- [x] 1.1 Observe screen sleep/wake independently of system sleep, refresh USB state and force settled display reconciliation; verify notification routing and display regression tests.
- [x] 1.2 Cover hub absent/present, unchanged topology, disabled switching, clamshell and overlapping system sleep; verify standalone regression checks pass (XCTest is unavailable in the installed Command Line Tools).
- [x] 1.3 Document screen wake recovery and verify README matches the behavior contract.

## 2. Validation

- [x] 2.1 Attempt full XCTest and record toolchain limitations; run standalone checks, release build and strict OpenSpec validation and verify these pass before syncing and archiving.

Validation: Apple Swift 6.4 release build passed; standalone checks passed with `PATH=/Library/Developer/CommandLineTools/usr/bin:$PATH sh scripts/run-checks.sh`; strict change validation passed. `xcrun swift test` cannot run because Command Line Tools lack XCTest. Updated stale keyboard test doubles required by the standalone runner. A physical screen-sleep/handover cycle remains to be observed after deployment.
