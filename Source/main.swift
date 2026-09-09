import AppKit
import Carbon
import ServiceManagement

private let hotkeySignature: OSType = 0x54465354 // TFST

// Carbon delivers application events on the main thread. Keep the C callback
// free of captured state and enter AppKit's main actor explicitly.
private let hotkeyCallback: EventHandlerUPP = { _, event, context in
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &identifier)
    guard result == noErr, identifier.signature == hotkeySignature,
          identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
    MainActor.assumeIsolated {
        Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().openTerminal()
    }
    return noErr
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var statusLine: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private func alert(_ title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    @discardableResult
    private func item(_ title: String, action: Selector?, menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier).count > 1 {
            NSApp.terminate(nil)
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⌘1"
        statusItem.button?.toolTip = "Terminal First"
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusLine = item("Terminal First — starting…", action: nil, menu: menu)
        statusLine.isEnabled = false
        menu.addItem(.separator())
        item("Open Terminal", action: #selector(openTerminal), menu: menu)
        toggleItem = item("Enable ⌘1", action: #selector(toggleHotkey), menu: menu)
        loginItem = item("Start at Login", action: #selector(toggleLogin), menu: menu)
        menu.addItem(.separator())
        item("About Terminal First", action: #selector(showAbout), menu: menu)
        item("Quit Terminal First", action: #selector(quit), menu: menu)
        statusItem.menu = menu
        refreshLogin()

        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), hotkeyCallback,
                                        1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else {
            statusLine.title = "Terminal First — unavailable"
            toggleItem.isEnabled = false
            alert("Unable to listen for ⌘1", message: "macOS returned error \(status). Quit and reopen the app from Finder.")
            return
        }
        if UserDefaults.standard.bool(forKey: "Paused") {
            statusLine.title = "Terminal First — paused"
            statusItem.button?.appearsDisabled = true
        } else {
            enableHotkey()
        }
    }

    private func enableHotkey() {
        guard hotkey == nil else { return }
        let identifier = EventHotKeyID(signature: hotkeySignature, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_1), UInt32(cmdKey), identifier,
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotkey)
        guard status == noErr else {
            statusLine.title = "Terminal First — shortcut unavailable"
            let message = status == eventHotKeyExistsErr
                ? "Another global shortcut utility is using this key. Disable its ⌘1 binding, then choose Enable ⌘1 here."
                : "macOS could not register the global shortcut. Quit and reopen the app from Finder."
            alert("Couldn’t reserve ⌘1", message: "\(message) macOS error: \(status).")
            return
        }
        statusLine.title = "Terminal First — ⌘1 active"
        toggleItem.title = "Pause ⌘1"
        statusItem.button?.appearsDisabled = false
        UserDefaults.standard.set(false, forKey: "Paused")
    }

    @objc private func toggleHotkey() {
        if let hotkey {
            let status = UnregisterEventHotKey(hotkey)
            guard status == noErr else {
                alert("Couldn’t pause ⌘1", message: "Quit the app to release the shortcut. macOS error: \(status).")
                return
            }
            self.hotkey = nil
            statusLine.title = "Terminal First — paused"
            toggleItem.title = "Enable ⌘1"
            statusItem.button?.appearsDisabled = true
            UserDefaults.standard.set(true, forKey: "Paused")
        } else {
            enableHotkey()
        }
    }

    @objc func openTerminal() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            alert("Terminal not found", message: "The Apple Terminal app could not be found on this Mac.")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
            if let error {
                let message = error.localizedDescription
                Task { @MainActor [weak self] in
                    self?.alert("Couldn’t open Terminal", message: message)
                }
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) { refreshLogin() }

    private func refreshLogin() {
        let status = SMAppService.mainApp.status
        loginItem.state = status == .enabled ? .on : .off
        loginItem.title = status == .requiresApproval ? "Approve Start at Login…" : "Start at Login"
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            alert("Login setting couldn’t be changed", message: "\(error.localizedDescription)\n\nMove Terminal First to Applications and try again. You can also add it in System Settings → General → Login Items.")
        }
        refreshLogin()
    }

    @objc private func showAbout() {
        refreshLogin()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1"
        alert("Terminal First \(version)", message: """
        Press ⌘1 to open or focus Apple Terminal.

        While active, this global shortcut takes priority over ordinary app shortcuts. Use Pause or Quit to restore their normal behavior.

        Uses the physical 1 key on the main keyboard. No network access, keystroke recording, or Accessibility permission is needed.

        For automatic startup, move the app to Applications and enable Start at Login.
        """)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
withExtendedLifetime(delegate) { app.run() }
