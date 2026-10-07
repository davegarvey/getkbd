## 1. Implement the automatic claim retry policy

- [x] 1.1 Replace the fixed automatic claim delay sequence with a two-minute elapsed-time fast phase that retries immediately after ordinary failed claims, while enforcing a five-second minimum start-to-start interval for failures that return sooner; verify focused ownership-controller tests cover the fast phase and the rapid-failure guard.
- [x] 1.2 Add the post-fast-phase waits of 15, 30, and 60 seconds, then stop claim retries; verify focused tests cover each delay and exhaustion.
- [x] 1.3 Preserve single-flight operation behavior, cancellation when the desired ownership changes, and existing release retry and manual-target behavior; verify focused tests cover these transitions and ensure no claim operations overlap.
- [x] 1.4 Reset the fast retry window when eligible local signals, startup, wake, or a failed Try Now attempt begin a new automatic cycle; verify focused tests cover each applicable reset path.

## 2. Validate the change

- [x] 2.1 Run focused standalone ownership-controller retry checks for the fast phase, single-flight behavior, slow backoff, and stop condition; add XCTest coverage for signal-reset behavior and transition coverage.
- [x] 2.2 Run `openspec validate responsive-keyboard-claim-retries --strict` and resolve any specification or artifact errors.
