import AppKit
import Carbon
import ServiceManagement
import SwiftUI

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

enum HotkeyState: Equatable {
    case active
    case paused
    case unavailable(String)
}

// MARK: - Window content

struct MainView: View {
    @ObservedObject var app: AppDelegate

    private var hotkeyBinding: Binding<Bool> {
        Binding(
            get: { MainActor.assumeIsolated { app.hotkeyState == .active } },
            set: { _ in MainActor.assumeIsolated { app.toggleHotkey() } }
        )
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { MainActor.assumeIsolated { app.loginEnabled } },
            set: { _ in MainActor.assumeIsolated { app.toggleLogin() } }
        )
    }

    private var badgeColor: Color {
        app.hotkeyState == .active ? Color.accentColor : Color.secondary
    }

    private var statusTitle: String {
        switch app.hotkeyState {
        case .active: return "⌘1 is active"
        case .paused: return "⌘1 is paused"
        case .unavailable: return "⌘1 is unavailable"
        }
    }

    private var statusDetail: String {
        switch app.hotkeyState {
        case .active:
            return "Press Command + 1 in any app to open or focus Apple Terminal."
        case .paused:
            return "Command + 1 behaves normally in other apps until you enable it again."
        case .unavailable(let reason):
            return reason
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Text("⌘1")
                    .font(.system(size: 60, weight: .semibold, design: .rounded))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(badgeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text(statusTitle)
                    .font(.title3.weight(.semibold))
                Text(statusDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: hotkeyBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable ⌘1 shortcut")
                            Text("Takes priority over ordinary app shortcuts while on.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!app.hotkeyAvailable)
                    Divider()
                    Toggle(isOn: loginBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start at Login")
                            Text(app.loginRequiresApproval
                                 ? "Waiting for approval in System Settings → Login Items."
                                 : "Launch Terminal First when you sign in.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if app.loginRequiresApproval {
                        Button("Open Login Items Settings…") { app.openLoginItemsSettings() }
                            .controlSize(.small)
                    }
                }
                .toggleStyle(.switch)
                .padding(6)
            }

            HStack {
                Button("Quit Terminal First") { app.quit() }
                Spacer()
                Button("Open Terminal") { app.openTerminal() }
                    .keyboardShortcut(.defaultAction)
            }

            Text("Version \(app.version) · No network, keystroke recording, or Accessibility permission.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(width: 400)
    }
}

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, ObservableObject {
    @Published private(set) var hotkeyState: HotkeyState = .paused
    @Published private(set) var hotkeyAvailable = true
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginRequiresApproval = false

    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2"

    private var statusItem: NSStatusItem!
    private var statusLine: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var window: NSWindow?
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
    private func item(_ title: String, action: Selector?, menu: NSMenu, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    private func setStatus(_ state: HotkeyState) {
        hotkeyState = state
        switch state {
        case .active:
            statusLine.title = "Terminal First — ⌘1 active"
            toggleItem.title = "Pause ⌘1"
            statusItem.button?.appearsDisabled = false
        case .paused:
            statusLine.title = "Terminal First — paused"
            toggleItem.title = "Enable ⌘1"
            statusItem.button?.appearsDisabled = true
        case .unavailable:
            statusLine.title = "Terminal First — shortcut unavailable"
            toggleItem.title = "Enable ⌘1"
            statusItem.button?.appearsDisabled = true
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier).count > 1 {
            NSApp.terminate(nil)
            return
        }
        installMainMenu()

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
        item("Open Terminal First…", action: #selector(showWindow), menu: menu)
        item("About Terminal First", action: #selector(showAbout), menu: menu)
        item("Quit Terminal First", action: #selector(quit), menu: menu)
        statusItem.menu = menu
        refreshLogin()

        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), hotkeyCallback,
                                        1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else {
            hotkeyAvailable = false
            toggleItem.isEnabled = false
            setStatus(.unavailable("macOS could not listen for the shortcut (error \(status)). Quit and reopen the app from Finder."))
            alert("Unable to listen for ⌘1", message: "macOS returned error \(status). Quit and reopen the app from Finder.")
            return
        }
        if UserDefaults.standard.bool(forKey: "Paused") {
            setStatus(.paused)
        } else {
            enableHotkey()
        }

        if !UserDefaults.standard.bool(forKey: "HasShownWindow") {
            UserDefaults.standard.set(true, forKey: "HasShownWindow")
            showWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWindow()
        return false
    }

    // Accessory apps show no menu bar, but a main menu still supplies ⌘W and ⌘Q
    // key equivalents while the window is frontmost.
    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit Terminal First", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }

    @objc func showWindow() {
        if window == nil {
            let hosting = NSHostingController(rootView: MainView(app: self))
            let window = NSWindow(contentRect: .zero,
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "Terminal First"
            window.contentViewController = hosting
            window.setContentSize(hosting.view.fittingSize)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        refreshLogin()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) { refreshLogin() }

    private func enableHotkey() {
        guard hotkey == nil else { return }
        let identifier = EventHotKeyID(signature: hotkeySignature, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_1), UInt32(cmdKey), identifier,
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotkey)
        guard status == noErr else {
            let message = status == eventHotKeyExistsErr
                ? "Another global shortcut utility is using this key. Disable its ⌘1 binding, then choose Enable ⌘1 here."
                : "macOS could not register the global shortcut. Quit and reopen the app from Finder."
            setStatus(.unavailable("\(message) macOS error: \(status)."))
            alert("Couldn’t reserve ⌘1", message: "\(message) macOS error: \(status).")
            return
        }
        setStatus(.active)
        UserDefaults.standard.set(false, forKey: "Paused")
    }

    @objc func toggleHotkey() {
        if let hotkey {
            let status = UnregisterEventHotKey(hotkey)
            guard status == noErr else {
                alert("Couldn’t pause ⌘1", message: "Quit the app to release the shortcut. macOS error: \(status).")
                return
            }
            self.hotkey = nil
            setStatus(.paused)
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
        loginEnabled = status == .enabled
        loginRequiresApproval = status == .requiresApproval
        loginItem.state = loginEnabled ? .on : .off
        loginItem.title = loginRequiresApproval ? "Approve Start at Login…" : "Start at Login"
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @objc func toggleLogin() {
        let service = SMAppService.mainApp
        if service.status == .requiresApproval {
            openLoginItemsSettings()
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
        alert("Terminal First \(version)", message: """
        Press ⌘1 to open or focus Apple Terminal.

        While active, this global shortcut takes priority over ordinary app shortcuts. Use Pause or Quit to restore their normal behavior.

        Uses the physical 1 key on the main keyboard. No network access, keystroke recording, or Accessibility permission is needed.

        For automatic startup, move the app to Applications and enable Start at Login.
        """)
    }

    @objc func quit() { NSApp.terminate(nil) }

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
