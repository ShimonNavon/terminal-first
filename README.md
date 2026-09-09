TERMINAL FIRST 1.0
macOS 13 Ventura or later • Intel and Apple Silicon

INSTALL
1. Extract Terminal First App.zip.
2. Drag Terminal First.app into Applications.
3. Open the app. A ⌘1 control appears in the menu bar.
4. Press Command + 1 to open or focus Apple Terminal.

MENU CONTROLS
Pause / Enable: release or reserve Command + 1.
Start at Login: optionally launch the app when you sign in.
Quit: stop the app and restore normal Command + 1 behavior.

The shortcut uses the physical 1 key on the main keyboard. It takes
priority over ordinary app shortcuts while active. Another exclusive
global hotkey utility can prevent registration; the app reports this.
No Accessibility or Input Monitoring permission is needed. The app does
not record keystrokes or use the network.

FIRST OPEN ON ANOTHER MAC
This build is locally signed, not Apple Developer ID signed or notarized.
macOS may block the first launch. If you trust this copy, use System
Settings > Privacy & Security > Open Anyway after attempting to open it.
Managed Macs may prohibit this. Do not disable Gatekeeper.

IF YOU USED THE EARLIER TERMINAL HELPER
That helper and this app cannot own Command + 1 simultaneously. To try
this app, first stop the old helper in Terminal:
launchctl bootout gui/$(id -u)/local.terminal-command-one
Then choose Enable ⌘1 in the new app. The old helper's login plist must
also be removed from ~/Library/LaunchAgents to prevent it returning at
login. Its name is local.terminal-command-one.plist.

UNINSTALL
Turn off Start at Login, quit Terminal First, then move the app to Trash.

BUILD FROM SOURCE
Install Apple's Command Line Tools, then run:
bash Source/build.sh
This creates Terminal First App.zip with both CPU architectures.
Source/Info.plist contains the app identity and minimum macOS version.

VALIDATION
Both architectures compile and the extracted app passes strict code
signature verification. Launch and shortcut-conflict reporting were
checked on macOS 26.6.2. Successful hotkey activation and login startup
of this packaged app have not been tested because the earlier helper
already owns the shortcut on the test Mac.

PUBLIC DISTRIBUTION
A Developer ID Application certificate and Apple notarization are needed
for a normal verified-developer distribution. Neither is included here.
