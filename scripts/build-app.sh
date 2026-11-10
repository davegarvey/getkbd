#!/bin/zsh

set -euo pipefail

configuration="${1:-release}"
root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -n "${GETKBD_ARCHS:-}" ]]; then
    architectures=(${=GETKBD_ARCHS})
else
    architectures=("$(uname -m)")
fi

binaries=()
for architecture in "${architectures[@]}"; do
    scratch_path="$root/.build/$configuration-$architecture"
    triple="$architecture-apple-macosx26.0"
    xcrun swift build --package-path "$root" -c "$configuration" \
        --triple "$triple" --scratch-path "$scratch_path"
    bin_path="$(xcrun swift build --package-path "$root" -c "$configuration" \
        --triple "$triple" --scratch-path "$scratch_path" --show-bin-path)"
    binaries+=("$bin_path/getkbd")
done

app="$root/.build/$configuration/getkbd.app"
contents="$app/Contents"

rm -rf "$app"
mkdir -p "$contents/MacOS"
if (( ${#binaries[@]} == 1 )); then
    cp "${binaries[1]}" "$contents/MacOS/getkbd"
else
    lipo -create "${binaries[@]}" -output "$contents/MacOS/getkbd"
fi
cp "$root/Sources/GetKbd/Resources/Info.plist" "$contents/Info.plist"
if [[ -n "${GETKBD_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $GETKBD_VERSION" \
        "$contents/Info.plist"
fi
if [[ -n "${GETKBD_BUILD:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $GETKBD_BUILD" \
        "$contents/Info.plist"
fi

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --deep --sign "$CODESIGN_IDENTITY" "$app"
else
    codesign --force --deep --sign - "$app"
    printf 'Ad-hoc signed app; set CODESIGN_IDENTITY for SMAppService login-item support.\n'
fi

printf 'Built %s\n' "$app"
