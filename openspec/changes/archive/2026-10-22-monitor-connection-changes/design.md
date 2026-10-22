## Context

On the test hardware (BenQ MA270S), moving the Thunderbolt and USB-C cables between the two Macs changed, on this Mac:

- the display UUID (`045A608D-…` to `2471A27F-…`); macOS keeps both in its display UUID map, so each monitor input presents its own EDID;
- which DDC input number belongs to this Mac (19 and 21 swap roles).

The KVM hubs (USB 3.0 hub 1059, USB 2.0 hub 21539) are the same devices on either cable. On Thunderbolt they sit behind the monitor's own Thunderbolt hubs (1056 and 21536), which stay connected whatever the monitor shows. An early reading mistook those for replacements of the KVM hubs; a later test showed the KVM hubs arriving unchanged.

## Goals / Non-Goals

**Goals:** keep detection, main-display switching and menu monitor switching working after a cable swap without a new setup; show one monitor entry in Settings.

**Non-Goals:** supporting two identical monitors with the same name at once; monitors whose KVM hubs differ per input.

## Decisions

### A monitor has several connections

Settings keep `selectedDisplay` (name and first identifier) and a list of connections, each with a display identifier and its learned inputs. The display monitor recognises the selected monitor by any known identifier first. Otherwise it accepts an online external display with the same name, but only when exactly one such display is online. It reports the new identifier, which is saved so that later recognition does not depend on the name.

Name matching is used because the EDID-derived identity differs per input. Vendor and model numbers might also differ between inputs, so they are not required to match.

### Input numbers are per connection and complete each other

A Mac's input changes with the cable, so inputs are stored per connection. The monitor has the same two inputs on every connection. When one input is learned on a new connection and an earlier connection's pair contains it, the other value is taken as the missing input. As a result, Switch Monitor to Other Mac is available as soon as this Mac's input is read after a swap. A value outside every known pair is not completed.

### Compatibility

Connections are written under `monitorConnections`. `monitorInputs` keeps being written with the original display's inputs, so an earlier build still works. Settings without `monitorConnections` are migrated to a single connection for the saved display.

## Risks / Trade-offs

- Renaming a monitor (macOS appends "(1)" when two identical monitors are attached) stops name recognition for new identities; known identities still match.
- A monitor with more than two inputs in use could complete a pair wrongly; the inference only applies with a fully learned pair and is overwritten when the other Mac's input is read directly.
