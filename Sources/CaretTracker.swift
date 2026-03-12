import Cocoa
import ApplicationServices

private func caretLog(_ msg: String) {
    let path = NSHomeDirectory() + "/mouselang_caret.log"
    let line = "\(Date()): \(msg)\n"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

class CaretTracker {
    var onCaretPositionChanged: ((NSPoint?) -> Void)?

    private var timer: Timer?
    private var lastPosition: NSPoint?
    private var lastHadCaret = false
    private var lastLoggedApp: String = ""

    func start() {
        caretLog("start() called")

        let trusted = AXIsProcessTrusted()
        caretLog("AXIsProcessTrusted = \(trusted)")

        if !trusted {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            caretLog("Requested accessibility permission")
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
        caretLog("Timer started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if lastHadCaret {
            lastHadCaret = false
            lastPosition = nil
            onCaretPositionChanged?(nil)
        }
    }

    private func poll() {
        let pos = queryCaretPosition()
        let hasCaret = pos != nil

        if pos != lastPosition || hasCaret != lastHadCaret {
            lastPosition = pos
            lastHadCaret = hasCaret
            onCaretPositionChanged?(pos)
        }
    }

    private func queryCaretPosition() -> NSPoint? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appName = frontApp.localizedName ?? "unknown"
        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // Get focused UI element — try 3 strategies
        var elemValue: AnyObject?

        // Strategy 1: App → FocusedUIElement (native apps)
        var focusResult = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &elemValue
        )

        // Strategy 2: SystemWide → FocusedUIElement
        if focusResult != .success {
            let systemWide = AXUIElementCreateSystemWide()
            focusResult = AXUIElementCopyAttributeValue(
                systemWide, kAXFocusedUIElementAttribute as CFString, &elemValue
            )
        }

        // Strategy 3: App → FocusedWindow → search for focused element
        if focusResult != .success {
            var windowValue: AnyObject?
            if AXUIElementCopyAttributeValue(
                appElement, kAXFocusedWindowAttribute as CFString, &windowValue
            ) == .success {
                let window = windowValue as! AXUIElement
                focusResult = AXUIElementCopyAttributeValue(
                    window, kAXFocusedUIElementAttribute as CFString, &elemValue
                )
            }
        }

        if focusResult != .success {
            if appName != lastLoggedApp {
                caretLog("[\(appName)] FAIL: focus error=\(focusResult.rawValue)")
                lastLoggedApp = appName
            }
            return nil
        }

        let element = elemValue as! AXUIElement

        // Get selected text range
        var rangeValue: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeValue
        )
        if rangeResult != .success {
            if appName != lastLoggedApp {
                var roleValue: AnyObject?
                AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
                let role = (roleValue as? String) ?? "unknown"
                caretLog("[\(appName)] FAIL: textRange error=\(rangeResult.rawValue) role=\(role)")
                lastLoggedApp = appName
            }
            return nil
        }

        var cfRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &cfRange) else {
            return nil
        }

        // Get bounds for the range
        var rect: CGRect? = nil

        // Strategy A: Direct range bounds
        rect = boundsForRange(element: element, range: rangeValue!)

        // Strategy B: Zero-length → try 1 char forward
        if rect == nil && cfRange.length == 0 {
            var fwdRange = CFRange(location: cfRange.location, length: 1)
            if let val = AXValueCreate(.cfRange, &fwdRange) {
                if let r = boundsForRange(element: element, range: val) {
                    rect = CGRect(x: r.origin.x, y: r.origin.y, width: 0, height: r.height)
                }
            }
        }

        // Strategy C: Zero-length → try 1 char backward
        if rect == nil && cfRange.length == 0 && cfRange.location > 0 {
            var bwdRange = CFRange(location: cfRange.location - 1, length: 1)
            if let val = AXValueCreate(.cfRange, &bwdRange) {
                if let r = boundsForRange(element: element, range: val) {
                    rect = CGRect(x: r.origin.x + r.width, y: r.origin.y, width: 0, height: r.height)
                }
            }
        }

        guard let finalRect = rect,
              finalRect.size.height > 0,
              finalRect.origin.x.isFinite,
              finalRect.origin.y.isFinite else {
            return nil
        }

        if appName != lastLoggedApp {
            caretLog("[\(appName)] OK")
            lastLoggedApp = appName
        }

        // AX coords (top-left origin) → AppKit coords (bottom-left origin)
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        let screenHeight = primaryScreen.frame.height
        let appKitY = screenHeight - finalRect.origin.y

        return NSPoint(x: finalRect.origin.x, y: appKitY)
    }

    private func boundsForRange(element: AXUIElement, range: AnyObject) -> CGRect? {
        var boundsValue: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &boundsValue
        ) == .success else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
        guard rect.size.height > 0 else { return nil }
        return rect
    }
}
