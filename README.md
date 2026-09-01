# getkbd

Move one Apple Magic Keyboard between two Macs using an external monitor.

## Requirements

- Two Macs running macOS 26 or later
- Apple Magic Keyboard
- External monitor
- Xcode Command Line Tools on each Mac

The default build is ad-hoc signed and does not require an Apple Developer account.

## Install

Run these commands on each Mac:

```sh
git clone https://github.com/davegarvey/getkbd.git
cd getkbd
./scripts/build-app.sh release
open .build/release/getkbd.app
```

You can drag `.build/release/getkbd.app` into `/Applications` after building.

If macOS blocks the app, Control-click it, choose **Open**, and confirm.

## Setup

1. Open **System Settings > Bluetooth** and pair the keyboard with each Mac.
2. Launch getkbd on both Macs.
3. Open **Settings** and select the keyboard and external monitor.
4. If a keyboard or monitor is missing, connect it and click **Refresh Keyboard and Monitor Lists**.

Automatic monitor switching is enabled by default. Optionally enable **Let the monitor take
ownership after a manual claim** in Settings.

## Use

For automatic switching, leave getkbd running on both Macs. Disconnecting the configured monitor
releases the keyboard; connecting it to the other Mac claims the keyboard there.

For manual switching:

1. Choose **Release Keyboard** on the Mac currently using the keyboard.
2. Choose **Get Keyboard** on the other Mac.

Keep the keyboard awake during pairing. If getkbd shows a passkey, type it on the keyboard and press
Return.

## Controls

- **Get Keyboard**: claim the selected keyboard.
- **Release Keyboard**: release the selected keyboard.
- **Settings**: change the keyboard, monitor, automatic behaviour, and shortcut.
- **Refresh Keyboard and Monitor Lists**: reload available Bluetooth keyboards and displays.

## Troubleshooting

- Pair the keyboard with both Macs before using getkbd.
- Wake or power-cycle the keyboard if pairing fails.
- The other Mac must be running getkbd for automatic release and claim.
- The built-in **Launch getkbd at login** option requires a signed build and will not work with the default ad-hoc signature.
