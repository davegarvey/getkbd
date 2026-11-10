# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-11-10

### Added

- switch the monitor input from the menu
- simplify menu and settings
- install app for Spotlight
- add Codex agent skills

### Changed

- Automate semantic releases with Grubble (#33)
- Add downloadable macOS releases (#32)
- Merge pull request #29 from davegarvey/codex/reconnect-hardening
- Merge main into reconnect-hardening
- Fix Bluetooth timeout helper isolation
- Trigger required pull request checks
- Merge pull request #31 from davegarvey/codex/contributing-guide
- Add contributor guide and MIT license
- Run Swift checks on pull requests (#30)
- Check cancelled reconnect avoids pairing fallback
- Distinguish reconnect cancellation from failure
- Bound reconnect operations and guard cancellation
- Merge pull request #26 from olsoloviov/claude/reconnect-existing-pairing
- Merge pull request #27 from davegarvey/claude/bluetoothd-restart-relaunch
- Relaunch getkbd after a Bluetooth service restart
- Prefer the live paired-devices object over a freshly constructed one
- Reconnect a keyboard still paired here instead of unpairing it
- Merge pull request #25 from davegarvey/claude/zero-address-recovery
- Re-resolve the keyboard before pairing and log its address
- Merge pull request #24 from davegarvey/claude/slow-claim-retry
- Keep the monitor switch available during keyboard operations
- Archive keep-retrying-unanswered-claims change
- Keep retrying an unanswered claim and say what helps
- Merge pull request #23 from davegarvey/claude/release-paired
- Archive warn-keyboard-held-while-bluetooth-off change
- Say when Bluetooth being off leaves the keyboard stuck here
- Archive release-paired-keyboard change
- Release a paired keyboard even when it is disconnected
- Merge pull request #22 from davegarvey/claude/cable-layouts
- Keep one hub group and complete inputs across connections
- Recognise the monitor across cable and input changes
- Merge pull request #21 from davegarvey/codex/responsive-keyboard-claim-retries
- Improve automatic keyboard claim retries
- Merge pull request #20 from davegarvey/codex/display-wake-recovery
- Recover primary display after screen-only wake
- Merge pull request #19 from davegarvey/codex/bluetooth-power
- Merge latest main into Bluetooth recovery PR
- Add Bluetooth power recovery
- Merge pull request #18 from davegarvey/claude/keyboard-reconnect-now-2dfc7e
- Add Try Now while getkbd is reconnecting the keyboard
- Merge pull request #17 from davegarvey/codex/keyboard-recovery
- Improve keyboard recovery and monitor switching setup
- Merge pull request #16 from davegarvey/fix/ownership-tests-stale-display
- remove stale display fake references
- Merge pull request #15 from davegarvey/claude/monitor-switching
- archive switch-monitor-input
- Merge pull request #14 from davegarvey/claude/simplify-ui
- remove stale device-list refresh scenario
- update configuration spec purpose
- archive simplify-ui
- Merge remote-tracking branch 'origin/main' into claude/simplify-ui
- Merge pull request #13 from davegarvey/claude/persist-logs
- Merge pull request #12 from davegarvey/codex/install-app-spotlight
- Merge pull request #11 from davegarvey/codex/openspec-agent-update
- refresh OpenCode workflows
- Merge pull request #9 from davegarvey/fix/post-wake-primary-display-sync
- Reconcile primary display after wake
- Merge pull request #8 from davegarvey/signal-driven-primary-display
- Switch primary display from USB hub signal
- Generalize monitor documentation and UI
- Merge pull request #7 from davegarvey/display-neutral-handoff
- Leave display configuration unchanged during handoff
- Merge pull request #6 from davegarvey/display-parking-overlay
- Keep KVM display signal online while parked
- Merge pull request #5 from davegarvey/usb-hub-display-parking
- Replace mirroring with hub-driven display parking
- Merge pull request #4 from davegarvey/guided-kvm-setup
- Document local display restoration
- Revamp settings UI
- Restore display after local activation
- Merge pull request #3 from davegarvey/guided-kvm-setup
- Restore display after local activation
- Merge pull request #2 from davegarvey/guided-kvm-setup
- Add guided KVM setup verification
- Add OpenSpec development commands
- Mirror displays during keyboard handoff (#1)
- Add current OpenSpec specifications
- Use local monitor and USB hub switching
- Clarify README default settings
- Simplify README getting started guide
- Improve keyboard handoff controls
- Improve Bluetooth keyboard handoff
- Add macOS keyboard switching app

### Fixed

- persist event log entries
