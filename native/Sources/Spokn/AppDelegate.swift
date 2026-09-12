import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanelController!
    private var integration: MacIntegration!
    private var status: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           let other = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            other.activate(); NSApp.terminate(nil); return
        }
        NSApp.setActivationPolicy(.accessory)
        panel = FloatingPanelController()
        integration = MacIntegration()
        integration.onCapture = { [weak self] result in
            switch result {
            case .success(let capture): self?.panel.receive(capture)
            case .failure(let error): self?.panel.showMessage(error.localizedDescription)
            }
        }
        let menu = NSMenu()
        add("Show Spokn", action: #selector(show), to: menu)
        add("Read Selection    ⌘⇧S", action: #selector(capture), to: menu)
        add("Paste and Read", action: #selector(paste), to: menu)
        add("Play / Pause", action: #selector(toggle), to: menu)
        add("Stop and Dismiss", action: #selector(stop), to: menu)
        menu.addItem(.separator())
        add("Hide After Playback", action: #selector(toggleAutoDismiss(_:)), to: menu)
        menu.items.last?.state = panel.dismissAfterPlayback ? .on : .off
        menu.addItem(.separator())
        add("Allow Selection Access…", action: #selector(accessibility), to: menu)
        add("Download System Voices…", action: #selector(voices), to: menu)
        menu.addItem(.separator())
        add("Quit Spokn", action: #selector(quit), to: menu, key: "q")
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = Design.symbol("waveform", "Spokn")
        status.menu = menu
        let main = NSMenu(); let application = NSMenuItem(); application.submenu = menu.copy() as? NSMenu; main.addItem(application)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        add("Paste and Read", action: #selector(paste), to: editMenu, key: "v")
        edit.submenu = editMenu; main.addItem(edit); NSApp.mainMenu = main
        if !integration.shortcutRegistered {
            panel.showMessage("⌘⇧S is already in use. Free it in the other app, then restart Spokn. You can paste here or use Read Selection in the menu bar.")
        } else { panel.show() }
        panel.reader.speech.warmLastVoice()
    }
    private func add(_ title: String, action: Selector, to menu: NSMenu, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { panel?.show(); return false }
    func applicationWillTerminate(_ notification: Notification) { panel?.reader.speech.stop() }
    @objc private func show() { panel.show() }
    @objc private func capture() { integration.capture() }
    @objc private func paste() { panel.paste() }
    @objc private func toggle() { panel.reader.toggle() }
    @objc private func stop() { integration.cancelCapture(); panel.dismiss() }
    @objc private func toggleAutoDismiss(_ sender: NSMenuItem) {
        panel.dismissAfterPlayback.toggle()
        // The app menu is a copy of the status menu; keep both checkmarks current.
        for menu in [status.menu, NSApp.mainMenu?.items.first?.submenu].compactMap({ $0 }) {
            menu.items.first(where: { $0.action == #selector(toggleAutoDismiss(_:)) })?.state = panel.dismissAfterPlayback ? .on : .off
        }
    }
    @objc private func accessibility() { MacIntegration.openAccessibility() }
    @objc private func voices() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent") { NSWorkspace.shared.open(url) }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
