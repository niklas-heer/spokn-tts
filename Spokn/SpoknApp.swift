import SwiftUI

@main
struct SpoknApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty scene - we're a menu bar app
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var appState: AppState!
    private var hotkeyManager: HotkeyManager!
    private var overlayWindow: NSWindow?
    private var overlayHostingView: NSHostingView<OverlayView>?
    private var settingsWindow: NSWindow?

    private static let hasLaunchedBeforeKey = "hasLaunchedBefore"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize app state
        appState = AppState()

        // Set up menu bar
        setupMenuBar()

        // Set up global hotkey (Cmd+Shift+S by default)
        setupHotkey()

        // Observe overlay visibility
        setupOverlayObserver()

        // Request accessibility permissions if needed
        requestAccessibilityPermissions()

        // Open settings on first launch
        if !UserDefaults.standard.bool(forKey: Self.hasLaunchedBeforeKey) {
            UserDefaults.standard.set(true, forKey: Self.hasLaunchedBeforeKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.openSettings()
            }
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Spokn")
        }

        let menu = NSMenu()

        // Read Selected Text
        let readItem = NSMenuItem(
            title: "Read Selected Text", action: #selector(readSelectedText), keyEquivalent: "s")
        readItem.keyEquivalentModifierMask = [.command, .shift]
        readItem.target = self
        menu.addItem(readItem)

        menu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Spokn", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyManager = HotkeyManager()

        // Register Cmd+Shift+S as the global hotkey
        hotkeyManager.register(
            keyCode: HotkeyManager.KeyCodes.s,
            modifiers: HotkeyManager.Modifiers.command | HotkeyManager.Modifiers.shift
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.appState.onHotkeyTriggered()
            }
        }
    }

    // MARK: - Overlay

    private func setupOverlayObserver() {
        // Watch for overlay visibility changes
        Task { @MainActor in
            for await isVisible in appState.$isOverlayVisible.values {
                if isVisible {
                    showOverlay()
                } else {
                    hideOverlay()
                }
            }
        }
    }

    private func showOverlay() {
        if overlayWindow == nil {
            createOverlayWindow()
        }

        overlayWindow?.orderFrontRegardless()
    }

    private func hideOverlay() {
        overlayWindow?.orderOut(nil)
    }

    private func createOverlayWindow() {
        // Create the overlay view
        let overlayView = OverlayView(appState: appState)
        let hostingView = NSHostingView(rootView: overlayView)

        // Calculate window frame - centered on screen, reasonable size
        guard let screen = NSScreen.main else { return }
        let windowWidth: CGFloat = 650
        let windowHeight: CGFloat = 400
        let windowX = (screen.frame.width - windowWidth) / 2
        let windowY = (screen.frame.height - windowHeight) / 2 + 100  // Slightly above center

        let windowFrame = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)

        // Create the window
        let window = NSPanel(
            contentRect: windowFrame,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true

        // Handle window close
        window.delegate = self

        overlayWindow = window
        overlayHostingView = hostingView
    }

    // MARK: - Actions

    @MainActor @objc private func readSelectedText() {
        appState.onHotkeyTriggered()
    }

    @objc private func openSettings() {
        // Reuse existing settings window if it exists
        if let existingWindow = settingsWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(appState: appState)
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Spokn Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 450, height: 400))
        window.center()
        window.makeKeyAndOrderFront(nil)

        settingsWindow = window

        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Permissions

    private func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if !trusted {
            print("Accessibility permissions needed for global hotkey and clipboard access")
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) == overlayWindow {
            Task { @MainActor in
                appState.closeOverlay()
            }
        }
    }
}
