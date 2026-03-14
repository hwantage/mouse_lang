import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var indicatorWindow: IndicatorWindow!
    private var inputSourceManager: InputSourceManager!
    private var isIndicatorEnabled = true
    private var toggleMenuItem: NSMenuItem!
    private var mouseTrackingTimer: Timer?
    private var lastMouseLocation: NSPoint = .zero

    private var currentTheme: Theme = .dark
    private var currentOpacity: CGFloat = 1.0
    private var themeMenuItems: [NSMenuItem] = []
    private var opacityMenuItems: [NSMenuItem] = []

    // Position offset from cursor
    private var offsetX: CGFloat = 18
    private var offsetY: CGFloat = -28
    private let offsetStep: CGFloat = 5
    private let defaultOffsetX: CGFloat = 18
    private let defaultOffsetY: CGFloat = -28
    private var positionLabel: NSMenuItem!

    // Adjustment mode
    private var isAdjustMode = false
    private var adjustModeMenuItem: NSMenuItem!
    private var scrollMonitor: Any?

    // Caret tracking
    private var caretTracker: CaretTracker!
    private var caretIndicatorWindow: IndicatorWindow!
    private var isCaretIndicatorEnabled = true
    private var caretToggleMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupIndicator()
        setupCaretTracker()
        setupInputSourceManager()
        startMouseTracking()
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "globe", accessibilityDescription: "MouseLang") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "가"
            }
        }

        let menu = NSMenu()

        // Toggle mouse indicator
        toggleMenuItem = NSMenuItem(
            title: "마우스 표시 끄기",
            action: #selector(toggleIndicator),
            keyEquivalent: "t"
        )
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        // Toggle caret indicator
        caretToggleMenuItem = NSMenuItem(
            title: "입력 커서 표시 끄기",
            action: #selector(toggleCaretIndicator),
            keyEquivalent: "i"
        )
        caretToggleMenuItem.target = self
        menu.addItem(caretToggleMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Theme submenu
        let themeSubmenu = NSMenu()
        for (index, theme) in Theme.allThemes.enumerated() {
            let item = NSMenuItem(
                title: theme.name,
                action: #selector(selectTheme(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            if index == 0 { item.state = .on }
            themeSubmenu.addItem(item)
            themeMenuItems.append(item)
        }
        let themeItem = NSMenuItem(title: "테마", action: nil, keyEquivalent: "")
        themeItem.submenu = themeSubmenu
        menu.addItem(themeItem)

        // Opacity submenu
        let opacitySubmenu = NSMenu()
        let opacityLevels: [(String, CGFloat)] = [
            ("100%", 1.0),
            ("80%", 0.8),
            ("60%", 0.6),
            ("40%", 0.4),
            ("20%", 0.2),
        ]
        for (index, (label, _)) in opacityLevels.enumerated() {
            let item = NSMenuItem(
                title: label,
                action: #selector(selectOpacity(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            if index == 0 { item.state = .on }
            opacitySubmenu.addItem(item)
            opacityMenuItems.append(item)
        }
        let opacityItem = NSMenuItem(title: "투명도", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacitySubmenu
        menu.addItem(opacityItem)

        // Position submenu
        let posSubmenu = NSMenu()

        positionLabel = NSMenuItem(title: positionLabelText(), action: nil, keyEquivalent: "")
        positionLabel.isEnabled = false
        posSubmenu.addItem(positionLabel)

        posSubmenu.addItem(NSMenuItem.separator())

        adjustModeMenuItem = NSMenuItem(
            title: "🎯 위치 조절 모드 (스크롤로 이동)",
            action: #selector(toggleAdjustMode),
            keyEquivalent: ""
        )
        adjustModeMenuItem.target = self
        posSubmenu.addItem(adjustModeMenuItem)

        posSubmenu.addItem(NSMenuItem.separator())

        let directions: [(String, Int)] = [
            ("↑ 위로", 0),
            ("↓ 아래로", 1),
            ("← 왼쪽으로", 2),
            ("→ 오른쪽으로", 3),
        ]
        for (title, tag) in directions {
            let item = NSMenuItem(
                title: title,
                action: #selector(movePosition(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = tag
            posSubmenu.addItem(item)
        }

        posSubmenu.addItem(NSMenuItem.separator())

        let resetItem = NSMenuItem(
            title: "↺ 초기화",
            action: #selector(resetPosition),
            keyEquivalent: ""
        )
        resetItem.target = self
        posSubmenu.addItem(resetItem)

        let posItem = NSMenuItem(title: "위치 조절", action: nil, keyEquivalent: "")
        posItem.submenu = posSubmenu
        menu.addItem(posItem)

        menu.addItem(NSMenuItem.separator())

        let debugItem = NSMenuItem(
            title: "AX 디버그 덤프",
            action: #selector(dumpAccessibilityFocus),
            keyEquivalent: "d"
        )
        debugItem.target = self
        menu.addItem(debugItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "종료",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Position Label

    private func positionLabelText() -> String {
        let xSign = offsetX >= 0 ? "+" : ""
        let ySign = offsetY >= 0 ? "+" : ""
        return "현재: X\(xSign)\(Int(offsetX)), Y\(ySign)\(Int(offsetY))"
    }

    private func refreshPositionLabel() {
        positionLabel.title = positionLabelText()
    }

    // MARK: - Indicator Window

    private func setupIndicator() {
        indicatorWindow = IndicatorWindow()
        indicatorWindow.applyTheme(currentTheme)
        indicatorWindow.applyOpacity(currentOpacity)

        let mouseLocation = NSEvent.mouseLocation
        indicatorWindow.moveTo(cursorLocation: mouseLocation, offsetX: offsetX, offsetY: offsetY)
    }

    // MARK: - Caret Tracker

    private func setupCaretTracker() {
        caretIndicatorWindow = IndicatorWindow()
        caretIndicatorWindow.applyTheme(currentTheme)
        caretIndicatorWindow.applyOpacity(currentOpacity)
        caretIndicatorWindow.orderOut(nil)

        caretTracker = CaretTracker()
        caretTracker.onCaretPositionChanged = { [weak self] position in
            guard let self = self, self.isCaretIndicatorEnabled else { return }
            if let pos = position {
                self.caretIndicatorWindow.moveAboveCaret(position: pos)
                self.caretIndicatorWindow.orderFront(nil)
            } else {
                self.caretIndicatorWindow.orderOut(nil)
            }
        }
        caretTracker.start()
    }

    // MARK: - Input Source Manager

    private func setupInputSourceManager() {
        inputSourceManager = InputSourceManager()

        inputSourceManager.onInputSourceChanged = { [weak self] isKorean in
            guard let self = self else { return }
            self.indicatorWindow.update(isKorean: isKorean)
            self.caretIndicatorWindow.update(isKorean: isKorean)
        }

        let isKorean = inputSourceManager.isCurrentInputSourceKorean()
        indicatorWindow.update(isKorean: isKorean)
        caretIndicatorWindow.update(isKorean: isKorean)
    }

    // MARK: - Mouse Tracking

    private func startMouseTracking() {
        mouseTrackingTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 60.0,
            repeats: true
        ) { [weak self] _ in
            self?.updateMousePosition()
        }

        if let timer = mouseTrackingTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func updateMousePosition() {
        guard isIndicatorEnabled else { return }

        let mouseLocation = NSEvent.mouseLocation

        if mouseLocation != lastMouseLocation {
            lastMouseLocation = mouseLocation
            indicatorWindow.moveTo(cursorLocation: mouseLocation, offsetX: offsetX, offsetY: offsetY)
        }
    }

    // MARK: - Adjustment Mode

    @objc private func toggleAdjustMode() {
        isAdjustMode.toggle()

        if isAdjustMode {
            adjustModeMenuItem.title = "🎯 위치 조절 모드 끄기"
            indicatorWindow.setAdjustMode(true)

            scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                self?.handleScrollAdjust(event)
            }
        } else {
            adjustModeMenuItem.title = "🎯 위치 조절 모드 (스크롤로 이동)"
            indicatorWindow.setAdjustMode(false)

            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
                scrollMonitor = nil
            }
        }
    }

    private func handleScrollAdjust(_ event: NSEvent) {
        guard isAdjustMode else { return }

        if event.modifierFlags.contains(.shift) {
            offsetX += event.scrollingDeltaY > 0 ? -2 : 2
        } else {
            offsetX += event.scrollingDeltaX > 0 ? 2 : -2
            offsetY += event.scrollingDeltaY > 0 ? 2 : -2
        }

        refreshPositionLabel()
        let mouseLocation = NSEvent.mouseLocation
        indicatorWindow.moveTo(cursorLocation: mouseLocation, offsetX: offsetX, offsetY: offsetY)
    }

    // MARK: - Actions

    @objc private func toggleIndicator() {
        isIndicatorEnabled.toggle()

        if isIndicatorEnabled {
            toggleMenuItem.title = "마우스 표시 끄기"
            indicatorWindow.orderFront(nil)
            let mouseLocation = NSEvent.mouseLocation
            indicatorWindow.moveTo(cursorLocation: mouseLocation, offsetX: offsetX, offsetY: offsetY)
        } else {
            toggleMenuItem.title = "마우스 표시 켜기"
            indicatorWindow.orderOut(nil)
        }
    }

    @objc private func toggleCaretIndicator() {
        isCaretIndicatorEnabled.toggle()

        if isCaretIndicatorEnabled {
            caretToggleMenuItem.title = "입력 커서 표시 끄기"
            caretTracker.start()
        } else {
            caretToggleMenuItem.title = "입력 커서 표시 켜기"
            caretTracker.stop()
            caretIndicatorWindow.orderOut(nil)
        }
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index < Theme.allThemes.count else { return }

        currentTheme = Theme.allThemes[index]
        indicatorWindow.applyTheme(currentTheme)
        caretIndicatorWindow.applyTheme(currentTheme)

        for item in themeMenuItems { item.state = .off }
        sender.state = .on
    }

    @objc private func selectOpacity(_ sender: NSMenuItem) {
        let opacityValues: [CGFloat] = [1.0, 0.8, 0.6, 0.4, 0.2]
        let index = sender.tag
        guard index < opacityValues.count else { return }

        currentOpacity = opacityValues[index]
        indicatorWindow.applyOpacity(currentOpacity)
        caretIndicatorWindow.applyOpacity(currentOpacity)

        for item in opacityMenuItems { item.state = .off }
        sender.state = .on
    }

    @objc private func movePosition(_ sender: NSMenuItem) {
        switch sender.tag {
        case 0: offsetY += offsetStep
        case 1: offsetY -= offsetStep
        case 2: offsetX -= offsetStep
        case 3: offsetX += offsetStep
        default: break
        }

        refreshPositionLabel()
        let mouseLocation = NSEvent.mouseLocation
        indicatorWindow.moveTo(cursorLocation: mouseLocation, offsetX: offsetX, offsetY: offsetY)
    }

    @objc private func resetPosition() {
        offsetX = defaultOffsetX
        offsetY = defaultOffsetY
        refreshPositionLabel()
        let mouseLocation = NSEvent.mouseLocation
        indicatorWindow.moveTo(cursorLocation: mouseLocation, offsetX: offsetX, offsetY: offsetY)
    }

    @objc private func dumpAccessibilityFocus() {
        caretTracker.dumpCurrentFocusContext()
    }

    @objc private func quitApp() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
        caretTracker.stop()
        mouseTrackingTimer?.invalidate()
        mouseTrackingTimer = nil
        NSApp.terminate(nil)
    }
}
