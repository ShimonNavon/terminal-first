# Terminal First

A Swift menu-bar app that reserves **Command + 1** to open or focus Apple Terminal, taking priority over ordinary app shortcuts.

Requires macOS 13 Ventura or later. One app supports Apple Silicon and Intel Macs.

## Install

1. Extract `Terminal First App.zip`.
2. Move `Terminal First.app` into Applications and open it.
3. Use the **⌘1** menu-bar control to pause/resume or enable **Start at Login**.

Quit or pause to restore ordinary Command + 1 behavior. The shortcut uses the physical 1 key on the main keyboard. Another exclusive global hotkey utility can prevent registration; the app reports this conflict.

No Accessibility or Input Monitoring permission is needed. The app does not record keystrokes or access the network.

## Build

Install Apple's Command Line Tools with a Swift 6 compiler, then run:

```sh
bash Source/build.sh
```

This compiles both architectures with Swift 6 checks and warnings treated as errors, creates a universal executable, locally signs and verifies the app, and writes `Terminal First App.zip`.

- `Source/main.swift`: AppKit menu, Carbon hotkey bridge, and ServiceManagement login settings.
- `Source/Info.plist`: app identity, version, and minimum macOS version.
- `Source/build.sh`: build and packaging steps.

Version 1.1 preserves the bundle identifier and `Paused` preference from version 1.0. Carbon application callbacks run on the main thread and enter Swift's main actor before using AppKit. The delegate remains alive throughout the event loop; the Carbon handler is removed on exit.

## First launch on another Mac

This build is locally signed, not Developer ID signed or notarized. macOS may block the first launch. If you trust the copy, use **System Settings → Privacy & Security → Open Anyway** after trying to open it. Managed Macs may prohibit this. Do not disable Gatekeeper.

A Developer ID Application certificate and Apple notarization are needed for verified-developer distribution; neither is included here.

## Earlier command-line helper

The earlier helper and this app cannot reserve Command + 1 simultaneously. If you installed that helper, stop it before enabling this app:

```sh
launchctl bootout gui/$(id -u)/local.terminal-command-one
```

Remove `local.terminal-command-one.plist` from `~/Library/LaunchAgents` to prevent the old helper returning at login.

## Uninstall

Turn off **Start at Login**, quit the app, then move it to Trash.

## Validation

Version 1.1 compiles for both architectures with Swift 6 checks and warnings as errors. The packaged app passes strict code-signature verification. Hotkey activation, pause/resume, and login startup of the Swift build still need an interactive test with the earlier helper stopped; those behaviors have not been verified end to end.
