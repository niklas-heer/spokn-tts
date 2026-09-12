import AppKit

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var onKey: ((NSEvent) -> Bool)?
    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }
    override func cancelOperation(_ sender: Any?) { orderOut(sender) }
}

final class FloatingPanelController: NSWindowController {
    let reader = ReaderController()
    private var dismissWork: DispatchWorkItem?
    private var keyMonitor: Any?
    private let preferences: UserDefaults
    var dismissAfterPlayback: Bool {
        get { preferences.bool(forKey: "native.dismissAfterPlayback") }
        set {
            preferences.set(newValue, forKey: "native.dismissAfterPlayback")
            cancelDismissal()
            if newValue, reader.speech.state == .finished { scheduleDismissal() }
        }
    }
    private weak var sourceApplication: NSRunningApplication?

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 480), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Spokn"; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isMovableByWindowBackground = true; panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        super.init(window: panel)
        panel.contentViewController = reader
        panel.setContentSize(NSSize(width: 720, height: 480))
        reader.onDismiss = { [weak self] in self?.dismiss() }
        reader.onPaste = { [weak self] in self?.paste() }
        reader.onInteraction = { [weak self] in self?.cancelDismissal() }
        reader.onFinish = { [weak self] in self?.scheduleDismissal() }
        panel.onKey = { [weak self] in self?.handleKey($0) ?? false }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.handleKey(event) ? nil : event
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    isolated deinit {
        dismissWork?.cancel()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
    func show() {
        cancelDismissal()
        reader.refreshEnvironment()
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.bundleIdentifier != Bundle.main.bundleIdentifier { sourceApplication = frontmost }
        guard let window else { return }
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = NSSize(width: min(720, visible.width - 40), height: min(480, visible.height - 40))
            window.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height), display: true)
        }
        window.alphaValue = 1
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(reader.textView)
    }
    func receive(_ capture: CapturedText) {
        guard capture.content.length <= 100_000 else { showMessage("That's a long passage. Select up to 100,000 characters at a time."); return }
        guard !capture.content.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { showMessage("Your clipboard is empty. Copy a passage, then press ⌘V."); return }
        show(); reader.load(capture)
    }
    func showMessage(_ message: String) { show(); reader.showWelcome(message: message) }
    @objc func paste() {
        guard let capture = MacIntegration.clipboard() else { showMessage("Copy a passage, then press ⌘V to start listening."); return }
        receive(capture)
    }
    func dismiss() {
        cancelDismissal(); reader.speech.stop(); window?.orderOut(nil)
        // Nonactivating panels normally leave source focus intact; restore only if needed.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier { sourceApplication?.activate() }
    }
    private func cancelDismissal() { dismissWork?.cancel(); dismissWork = nil }
    private func scheduleDismissal() {
        cancelDismissal()
        guard dismissAfterPlayback else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.dismissAfterPlayback, self.reader.speech.state == .finished else { return }
            self.window?.orderOut(nil)
        }
        dismissWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
    private func handleKey(_ event: NSEvent) -> Bool {
        reader.revealControlsForKeyboard()
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 { dismiss(); return true }
        if modifiers.contains(.command), event.charactersIgnoringModifiers == "v" { paste(); return true }
        guard modifiers.intersection([.command, .control, .option]).isEmpty else { return false }
        if [123, 124].contains(event.keyCode), window?.firstResponder is NSSlider { return false }
        switch event.keyCode {
        case 49: reader.toggle(); return true
        case 123: reader.back(); return true
        case 124: reader.forward(); return true
        default: return false
        }
    }
}
