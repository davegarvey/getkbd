## Context

On the test hardware (BenQ MA270S), moving the Thunderbolt and USB-C cables between the two Macs changed, on this Mac:

- the display UUID (`045A608D-…` to `2471A27F-…`); macOS keeps both in its display UUID map, so each monitor input presents its own EDID;
- the KVM hubs' product IDs (USB 2.0 hub 21539 to 21536, USB 3.0 hub 1059 to 1056), with the same vendor and names; these are different hub chips behind each upstream port;
- which DDC input number belongs to this Mac (19 and 21 swap roles).

## Goals / Non-Goals

**Goals:** keep working after a cable swap with at most one ordinary monitor switch; never claim the keyboard because of a hub that has not been seen switching with the monitor; show one monitor entry in Settings.

**Non-Goals:** supporting two identical monitors with the same name at once; recognising a new connection's hubs before any switch.

## Decisions

### A monitor has several connections

Settings keep `selectedDisplay` (name and first identifier) and a list of connections. Each connection holds a display identifier, its hub group and its learned inputs. The display monitor recognises the selected monitor by any known identifier first. Otherwise it accepts an online external display with the same name, but only when exactly one such display is online, and reports the new identifier so that it is saved as a new connection.

Name matching is used because the EDID-derived identity differs per input. Vendor and model numbers might also differ between inputs, so they are not required to match.

### Hubs are learned per connection, not matched by name

The two connections use different hub chips with generic names ("4-Port USB 3.0 Hub") that many inexpensive hubs and docks share. Matching by vendor and name would risk claiming the keyboard whenever such a hub is plugged in. Instead, while the current connection has no hub group, a background identifier runs the existing switch-away-and-back detection. It keeps waiting for the first switch indefinitely, and abandons a half-finished switch after two minutes so that a hub plugged in and removed much later is not mistaken for the monitor's.

The overall hub group is the union of all connections' groups. Hubs from another connection are not reachable through the current cable, so the union does not create false presence.

### Input numbers are per connection

Inputs are learned only for a connection with a hub group. Without one, an absent group would be read as "showing the other Mac" and record this Mac's own input as the other Mac's.

### Compatibility

New settings are written under `monitorConnections`. The legacy keys `selectedUSBHubs`, `selectedUSBHub` and `monitorInputs` keep being written (union of hubs; inputs of the original display), so an earlier build still works. Settings without `monitorConnections` are migrated to a single connection for the saved display.

## Risks / Trade-offs

- The first switch after a cable swap does not move the keyboard. The menu says what to do.
- A hub plugged in and removed within two minutes while a new connection is being learned could be learned as part of the group. This is the same exposure as manual setup.
- Renaming a monitor (macOS appends "(1)" when two identical monitors are attached) stops name recognition for new identities; known identities still match.
