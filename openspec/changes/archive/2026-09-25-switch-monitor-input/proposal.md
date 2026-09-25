## Why

getkbd follows the monitor input, but the user must change that input with the
monitor's buttons or the manufacturer's software. On the Mac the monitor is not
showing, the menu currently offers no action at all, although that is exactly
where the user wants the monitor back. Tests on a BenQ MA270S connected to an
Apple Silicon Mac showed that getkbd can read the monitor's current input and
change it over the display cable (DDC/CI) using only interfaces built into macOS,
from either Mac, including while the monitor is showing the other Mac.

## What Changes

- Add **Switch Monitor to Other Mac** to the menu on the Mac the monitor is
  showing, and **Switch Monitor to This Mac** on the Mac it is not showing. Each
  sends one input-change command; the existing USB-hub handoff then moves the
  keyboard and main display as it does for a manual switch at the monitor.
- Learn the two input numbers without user involvement: read the monitor's input
  after each settled hub-group transition, recording it as this Mac's input when
  the group is present and the other Mac's input when it is absent.
- Show a monitor action only when the needed input number is known and the
  monitor can be reached. When it cannot, the menu behaves as it does today.
- No new settings, permissions, helper tools or network use.

## Capabilities

### New Capabilities

- `monitor-input-switching`: reading and changing the selected monitor's input
  over the display connection, and learning which input belongs to each Mac.

### Modified Capabilities

- `configuration-and-controls`: the menu may show one monitor action alongside
  the keyboard action, and the persisted settings include the learned inputs.

## Impact

- Code: a new DDC/CI adapter and input learner; `MenuStatus` and
  `MenuBarController` gain the monitor action; `AppSettings` gains learned
  inputs; `AppDelegate` wires hub transitions to learning.
- Relies on undocumented IOKit functions (`IOAVServiceCreateWithService`,
  `IOAVServiceReadI2C`, `IOAVServiceWriteI2C`) available on Apple Silicon. On Macs
  or connections where they do not work, the monitor actions are hidden and the
  rest of getkbd is unaffected.
- Documentation: the README describes the new menu actions and supported
  hardware.
