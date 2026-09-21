#!/bin/zsh

set -euo pipefail

if (( $# > 1 )); then
    print -u2 "Usage: $0 [Applications directory]"
    exit 2
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
applications_dir="${1:-$HOME/Applications}"
app_source="$root/.build/release/getkbd.app"
app_destination="$applications_dir/getkbd.app"

"$root/scripts/build-app.sh" release
mkdir -p "$applications_dir"
ditto "$app_source" "$app_destination"

if ! diff -qr "$app_source" "$app_destination" >/dev/null; then
    print -u2 "Installed app does not match the built app: $app_destination"
    exit 1
fi

codesign --verify --deep --strict "$app_destination"
printf 'Installed and verified %s\n' "$app_destination"
