## Context

See proposal.md. SleepMonitor observes system sleep/wake only. DisplayMonitor forces reconciliation for system wake, but ignores screen notifications when display topology stays unchanged.

## Goals / Non-Goals

Goals: recover the preferred primary display on screen-only wake using fresh USB state and existing settling debounce.
Non-goals: move windows, alter display enablement, or reset keyboard manual intent on screen wake.

## Decisions

Observe screensDidSleep and screensDidWake through the existing workspace notification center. Track screen sleep independently of system sleep in DisplayMonitor, so a screen-wake notification cannot override a real system-sleep guard. On screen wake refresh the USB monitor while display synchronization is suspended, then clear screen sleep and force the existing debounced evaluation. USB transitions continue to drive keyboard ownership normally; screen events alone do not call OwnershipController wake. Reusing whole-system wake was rejected because it clears manual keyboard intent. Periodic polling was rejected because explicit screen wake supplies the missing trigger.

## Risks / Trade-offs

- Notification order varies: independent sleep flags retain system-sleep protection and repeated wake events coalesce through debounce.
- Built-in display may remain inactive in clamshell mode: retain the existing active-screen guard.
- Window relocation remains macOS behavior: retain existing placement and restoration semantics.

## Migration Plan

Run XCTest, standalone checks, strict OpenSpec validation and release build. Sync and archive specs, merge the PR, install the merged release, stop the previous process and launch the installed app. Roll back by rebuilding the previous commit if needed. Hardware screen-sleep handover still requires a real subsequent cycle.
