import Cocoa
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover?
    private var popoverClickMonitor: Any?
    private var popoverWorkspaceObservers: [NSObjectProtocol] = []
    private let eventTapManager = EventTapManager.shared
    private var batteryObserver: NSObjectProtocol?
    private var profileObserver: NSObjectProtocol?
    private var didAlertLowBattery = false
    private var useEmojiInStatus = false
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let opensMappingsInBackground = CommandLine.arguments.contains("--show-mappings-in-background")

        // Ensure Accessibility permissions
        PermissionManager.shared.ensureAccessibilityPermission(showPrompt: !opensMappingsInBackground)

        // Load configuration (profiles, settings)
        ConfigManager.shared.load()

        // Start HID listener (filters Naga device presses)
        _ = HIDListener.shared

        // Start battery monitoring for the USB receiver and Bluetooth.
        BatteryMonitor.shared.start()

        // Fire-and-forget: at most once a day, posts a notification if a newer release
        // exists. No auto-update, just visibility.
        UpdateChecker.shared.checkIfNeeded()

        // Status bar item (variable length to show %). This is a bonus, convenient path
        // to the popover — but its rendering has been observed to silently fail even with
        // an autosaveName set and free space in the menu bar (see upstream #9 and #11),
        // and AppKit's own visibility flags (`isVisible`, `button.window?.isVisible`)
        // don't reliably reflect that failure either. Reachability must not depend on
        // this succeeding: the Dock icon and main window below are the guaranteed way in.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "NagaController.statusItem"
        if let button = statusItem.button {
            if let icon = NSImage(named: "MenuBar") {
                icon.isTemplate = true
                button.image = icon
                button.imagePosition = .imageLeading
            } else {
                // Fallback to an SF Symbol if available; else use emoji in the title
                if let sym = UIStyle.symbol("computermouse", size: 14, weight: .regular)
                    ?? UIStyle.symbol("mouse", size: 14, weight: .regular)
                    ?? UIStyle.symbol("battery.100", size: 14, weight: .regular) {
                    sym.isTemplate = true
                    button.image = sym
                    button.imagePosition = .imageLeading
                } else {
                    useEmojiInStatus = true
                }
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // Notifications (low battery alerts)
        requestNotificationAuthorizationIfPossible()

        // Observe battery updates
        batteryObserver = NotificationCenter.default.addObserver(forName: BatteryMonitor.didUpdateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleBatteryUpdate()
        }
        // Initialize status item text
        profileObserver = NotificationCenter.default.addObserver(
            forName: ConfigManager.profileDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateStatusItemBattery(level: BatteryMonitor.shared.batteryLevel)
        }
        updateStatusItemBattery(level: BatteryMonitor.shared.batteryLevel)

        // Reachability must not depend on the status item rendering. The app stays a
        // menu-bar app by default, but (a) the main window opens on the very first launch,
        // (b) opening the app again while it runs (Finder, Spotlight, the Dock) always
        // brings the window back via applicationShouldHandleReopen, and (c) a "Show icon
        // in Dock" preference switches the activation policy for anyone who wants it.
        AppDelegate.applyDockIconPreference()
        let firstLaunchKey = "NagaController.didShowFirstLaunchWindow"
        if opensMappingsInBackground {
            MappingWindowController.shared.show(activate: false)
        } else if !UserDefaults.standard.bool(forKey: firstLaunchKey) {
            UserDefaults.standard.set(true, forKey: firstLaunchKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showMainWindow()
            }
        }

        // Start event tap based on persisted setting
        let remapEnabled = ConfigManager.shared.getRemappingEnabled()
        eventTapManager.start(listenOnly: !remapEnabled, showPermissionPrompt: !opensMappingsInBackground)
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTapManager.stop()
        popover?.close()
        stopMonitoringPopover()
        if let profileObserver { NotificationCenter.default.removeObserver(profileObserver) }
    }

    // Opening the app again while it's running — Finder, Spotlight, `open`, or the Dock
    // icon when enabled — always brings the window back. This is the guaranteed way in;
    // it does not depend on the menu bar icon having rendered, and it works for
    // accessory (LSUIElement) apps too.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    static let showDockIconKey = "NagaController.showDockIcon"

    /// Applies the persisted "Show icon in Dock" preference. Default is off (menu-bar only).
    static func applyDockIconPreference() {
        let show = UserDefaults.standard.bool(forKey: showDockIconKey)
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }
        let controller = MainViewController()
        let window = NSWindow(contentViewController: controller)
        // The main view is styled for a dark background (white labels on HUD material);
        // the popover forces that, a standalone window would follow the system appearance
        // and render unreadable in Light mode.
        window.appearance = NSAppearance(named: .darkAqua)
        window.title = "NagaController"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        mainWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if let popover {
            popover.close()
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.appearance = NSAppearance(named: .vibrantDark)
        popover.contentViewController = MainViewController()
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if !popover.isShown, self.popover === popover {
            stopMonitoringPopover()
            self.popover = nil
        }
    }

    func popoverWillShow(_ notification: Notification) {
        guard let shown = notification.object as? NSPopover, popover === shown else { return }
        stopMonitoringPopover()
        // A menu-bar app can show its popover while another app still owns focus.
        // Observe outside clicks without intercepting them or activating this app.
        popoverClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self, weak shown] event in
            guard let self, let shown, self.popover === shown else { return }
            self.dismissPopoverOnOutsideClick(event, popover: shown)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        popoverWorkspaceObservers = [
            workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self, weak shown] _ in
                guard let self, let shown, self.popover === shown else { return }
                shown.close()
            },
            workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self, weak shown] note in
                guard let self, let shown, self.popover === shown,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                shown.close()
            }
        ]
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover, popover === closed else { return }
        stopMonitoringPopover()
        // Release the status item anchor with this presentation.
        popover = nil
    }

    private func stopMonitoringPopover() {
        if let monitor = popoverClickMonitor {
            NSEvent.removeMonitor(monitor)
            popoverClickMonitor = nil
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in popoverWorkspaceObservers {
            workspace.removeObserver(observer)
        }
        popoverWorkspaceObservers.removeAll()
    }

    private func dismissPopoverOnOutsideClick(_ event: NSEvent, popover: NSPopover) {
        guard popover.isShown else { return }
        let location = event.window?.convertPoint(toScreen: event.locationInWindow)
            ?? event.locationInWindow

        if popover.contentViewController?.view.window?.frame.contains(location) == true {
            return
        }
        if let button = statusItem.button, let window = button.window {
            let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
            // Let the status button's own action handle a repeat click.
            if buttonFrame.contains(location) { return }
        }
        popover.close()
    }

    private func handleBatteryUpdate() {
        let level = BatteryMonitor.shared.batteryLevel
        updateStatusItemBattery(level: level)
        guard let lvl = level else { return }
        if lvl <= 20 && !didAlertLowBattery {
            didAlertLowBattery = true
            let content = UNMutableNotificationContent()
            content.title = L10n.text("Mouse battery low")
            content.body = L10n.text("Your Naga battery is at %ld%%", lvl)
            let req = UNNotificationRequest(identifier: "naga.lowbattery", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
        }
        if lvl >= 25 {
            didAlertLowBattery = false
        }
    }

    private func updateStatusItemBattery(level: Int?) {
        guard let button = statusItem.button else { return }
        let hasImage = (button.image != nil)
        let profile = ConfigManager.shared.currentProfileName
        if let lvl = level {
            button.title = (hasImage ? " " : "🖱️ ") + "\(lvl)% · \(profile)"
            button.toolTip = L10n.text("Naga battery: %ld%% · Profile: %@", lvl, profile)
        } else {
            button.title = (hasImage ? " " : "🖱️ ") + profile
            button.toolTip = L10n.text("Naga battery: — · Profile: %@", profile)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === mainWindow else { return }
        mainWindow = nil
    }

    private func requestNotificationAuthorizationIfPossible() {
        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("[Notifications] Skipping authorization; bundle identifier missing (likely running via swift run).")
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
