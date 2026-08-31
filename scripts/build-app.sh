#!/bin/zsh

set -euo pipefail

configuration="${1:-release}"
root="$(cd "$(dirname "$0")/.." && pwd)"
swift build --package-path "$root" -c "$configuration"
bin_path="$(swift build --package-path "$root" -c "$configuration" --show-bin-path)"
app="$root/.build/$configuration/getkbd.app"
contents="$app/Contents"

rm -rf "$app"
mkdir -p "$contents/MacOS"
cp "$bin_path/getkbd" "$contents/MacOS/getkbd"
cp "$root/Sources/GetKbd/Resources/Info.plist" "$contents/Info.plist"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --deep --sign "$CODESIGN_IDENTITY" "$app"
else
    codesign --force --deep --sign - "$app"
    printf 'Ad-hoc signed app; set CODESIGN_IDENTITY for SMAppService login-item support.\n'
fi

printf 'Built %s\n' "$app"
