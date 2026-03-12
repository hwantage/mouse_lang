import Cocoa

// MARK: - Custom View for Drawing the Indicator

class IndicatorView: NSView {
    var text: String = "A" {
        didSet { needsDisplay = true }
    }

    var isKorean: Bool = false {
        didSet { needsDisplay = true }
    }

    var theme: Theme = .dark {
        didSet { needsDisplay = true }
    }

    var isAdjustMode: Bool = false {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bgRect = bounds.insetBy(dx: 1, dy: 1)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 5, yRadius: 5)

        // Background from theme
        let bgColor = isKorean ? theme.koreanBg : theme.englishBg
        bgColor.setFill()
        bgPath.fill()

        // Border — highlight in adjust mode
        if isAdjustMode {
            NSColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 0.9).setStroke()
            bgPath.lineWidth = 2.0
        } else {
            theme.borderColor.setStroke()
            bgPath.lineWidth = theme.borderWidth
        }
        bgPath.stroke()

        // Text with theme color
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: theme.textColor,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        (text as NSString).draw(at: point, withAttributes: attrs)
    }
}

// MARK: - Floating Indicator Window

class IndicatorWindow: NSWindow {
    private let indicatorView: IndicatorView

    init() {
        let frame = NSRect(x: 0, y: 0, width: 28, height: 22)
        indicatorView = IndicatorView(frame: frame)

        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .stationary]

        self.contentView = indicatorView
        self.orderFront(nil)
    }

    func update(isKorean: Bool) {
        indicatorView.isKorean = isKorean
        indicatorView.text = isKorean ? "한" : "A"
    }

    func applyTheme(_ theme: Theme) {
        indicatorView.theme = theme
    }

    func applyOpacity(_ opacity: CGFloat) {
        self.alphaValue = opacity
    }

    func setAdjustMode(_ on: Bool) {
        indicatorView.isAdjustMode = on
    }

    func moveTo(cursorLocation: NSPoint, offsetX: CGFloat, offsetY: CGFloat) {
        let x = cursorLocation.x + offsetX
        let y = cursorLocation.y + offsetY
        self.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Position above the text caret (for caret indicator)
    func moveAboveCaret(position: NSPoint) {
        let x = position.x - 14  // center the 28px indicator
        let y = position.y + 4   // 4px gap above caret
        self.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
