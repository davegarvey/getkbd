## 1. Audit

- [x] 1.1 Read the current Swift implementation, README, package manifest, build script, and tests; verify the behavior inventory against `git log --oneline -10`

## 2. Capability Specifications

- [x] 2.1 Add the `keyboard-handoff` baseline requirements and scenarios; verify the delta has valid Purpose, ADDED Requirements, and four-hash scenario headings
- [x] 2.2 Add the `device-detection` baseline requirements and scenarios; verify the delta covers keyboard, display, and USB hub signals
- [x] 2.3 Add the `configuration-and-controls` baseline requirements and scenarios; verify the delta covers persistence, UI, shortcut, login, and lifecycle behavior

## 3. Project Context and Sync

- [x] 3.1 Replace the template-only OpenSpec config with current project context; verify it remains valid YAML
- [x] 3.2 Sync the baseline deltas into main specs and validate all main specs with `openspec validate --specs`
