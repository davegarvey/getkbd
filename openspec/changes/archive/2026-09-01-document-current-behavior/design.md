## Context

See `proposal.md` for motivation. The repository is a small Swift 6.2 command-
line-built macOS 26+ AppKit application with no existing main specifications.
The current implementation is split between Bluetooth control, an ownership
state machine, local display and USB observers, and menu-bar/settings services.

## Goals / Non-Goals

**Goals:**

- Establish a durable, user-observable contract for the behavior already
  present at the current repository revision.
- Separate device signals, ownership decisions, and configuration/UI concerns
  so future changes can update only the affected capability.
- Preserve safety-relevant limitations, especially KVM's joint monitor/hub gate
  and lack of cross-Mac arbitration.

**Non-Goals:**

- Change Swift implementation, UI wording, persistence format, or tests.
- Add network coordination, remote ownership, or a distributed lock.
- Expand support beyond the local macOS APIs currently used by the app.

## Decisions

- Use three flat capability paths: `keyboard-handoff`, `device-detection`, and
  `configuration-and-controls`. This matches the app's actual boundaries and
  avoids one large specification that mixes state transitions with UI details.
- Record externally observable behavior and safety conditions rather than
  private class names or framework calls. Exact API choices remain free to
  change as long as the contract is preserved.
- Treat the current implementation and README as the baseline for this
  documentation change. Known limitations are stated where they affect safe
  operation; no corrective runtime work is included.
- Add project context to `openspec/config.yaml` so future artifacts inherit the
  platform, build, and local-only constraints.

## Risks / Trade-offs

- [Risk] The current Bluetooth handoff removes the local pairing, which is
  necessary for cross-Mac handoff but is more destructive than closing a
  connection. -> The behavior is explicit in the handoff requirements and
  should remain visible in future proposals.
- [Risk] Two Macs can see the same KVM hub at once. -> The spec records that
  getkbd has no cross-Mac arbitration and requires the physical hub to expose a
  unique active-host signal.
- [Risk] The implementation has limited integration-test coverage for real
  Bluetooth, IOKit, display, login-item, and UI APIs. -> The baseline documents
  the contract; future changes should add focused tests when those behaviors
  are modified.
