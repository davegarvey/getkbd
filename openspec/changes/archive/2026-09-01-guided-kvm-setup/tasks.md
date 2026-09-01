## 1. Model Setup and Peer State

- [x] 1.1 Add persisted peer identity, pairing, verification, and KVM-test state
      models with backward-compatible decoding.
- [x] 1.2 Add display-handoff phase and error state to the observable ownership
      snapshot.

## 2. Add Local Peer Verification

- [x] 2.1 Add a local-network peer advertiser/browser and a versioned message
      channel with explicit short-code confirmation.
- [x] 2.2 Persist paired-peer state separately from existing keyboard/display
      settings and handle unavailable or invalid peers without blocking startup.
- [x] 2.3 Exchange setup status and correlate before/after USB-hub snapshots for
      a verification session, including unsafe and ambiguous outcomes.

## 3. Integrate Handoff and Detection State

- [x] 3.1 Publish display preparation, protection, restoration, and failure state
      from the display monitor through ownership updates.
- [x] 3.2 Feed local ownership and device changes into peer status and KVM-test
      progress without making peer state authoritative for local ownership.
- [x] 3.3 Preserve local-only hub identification and manual switching when peer
      verification is unavailable.

## 4. Build the Guided Setup Experience

- [x] 4.1 Add a readiness summary and source choices phrased as cable swap,
      monitor-input switching, or manual switching.
- [x] 4.2 Make the monitor-input path guide peer discovery, pairing, hub
      detection, and the end-to-end switch test.
- [x] 4.3 Add source-specific requirements, actionable failure states, skip-as-
      unverified behavior, and live keyboard/display/peer status updates.
- [x] 4.4 Keep raw hub selection and technical details as fallback or advanced
      controls rather than the primary path.

## 5. Improve Daily Status and Recovery

- [x] 5.1 Update the menu-bar menu to prioritize the current action and show
      readiness, peer verification, and display-handoff status.
- [x] 5.2 Add retry and Display Settings recovery for keyboard and display-layout
      failures, plus detailed login-item status.
- [x] 5.3 Add local-network permission and Bonjour declarations with user-facing
      explanation.

## 6. Verify the Change

- [x] 6.1 Add focused tests for peer message validation, hub correlation,
      peer-unavailable fallback, and unsafe duplicate visibility.
- [x] 6.2 Add tests for KVM test progression and display-handoff state reporting.
- [x] 6.3 Run `swift build`, `swift test` where the platform test runtime is
      available, and the standalone `bash scripts/run-checks.sh` harness.
- [x] 6.4 Manually verify the two-Mac KVM flow with the monitor input switch.
