#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUTPUT="$ROOT/.build/debug/getkbd-checks"
SDKROOT=$(xcrun --show-sdk-path)

swiftc \
    -parse-as-library \
    -sdk "$SDKROOT" \
    -module-name GetKbdChecks \
    -o "$OUTPUT" \
    "$ROOT/Sources/GetKbd/AppDelegate.swift" \
    "$ROOT/Sources/GetKbd/DisplayMonitor.swift" \
    "$ROOT/Sources/GetKbd/KeyboardController.swift" \
    "$ROOT/Sources/GetKbd/Logging.swift" \
    "$ROOT/Sources/GetKbd/LoginItemController.swift" \
    "$ROOT/Sources/GetKbd/MenuBarController.swift" \
    "$ROOT/Sources/GetKbd/Models.swift" \
    "$ROOT/Sources/GetKbd/OwnershipController.swift" \
    "$ROOT/Sources/GetKbd/PeerStore.swift" \
    "$ROOT/Sources/GetKbd/PeerVerification.swift" \
    "$ROOT/Sources/GetKbd/SettingsStore.swift" \
    "$ROOT/Sources/GetKbd/SettingsWindowController.swift" \
    "$ROOT/Sources/GetKbd/SettingsView.swift" \
    "$ROOT/Sources/GetKbd/ShortcutController.swift" \
    "$ROOT/Sources/GetKbd/SleepMonitor.swift" \
    "$ROOT/Sources/GetKbd/USBHubMonitor.swift" \
    "$ROOT/Checks/GetKbdChecks/main.swift" \
    -framework AppKit \
    -framework Carbon \
    -framework ColorSync \
    -framework IOBluetooth \
    -framework IOKit \
    -framework Network \
    -framework ServiceManagement

"$OUTPUT"
