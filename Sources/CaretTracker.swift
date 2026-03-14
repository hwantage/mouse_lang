import Cocoa
import ApplicationServices

private let axSelectedTextMarkerRangeAttribute = "AXSelectedTextMarkerRange" as CFString
private let axTextInputMarkedTextMarkerRangeAttribute = "AXTextInputMarkedTextMarkerRange" as CFString
private let axBoundsForTextMarkerRangeParameterizedAttribute = "AXBoundsForTextMarkerRange" as CFString
private let axTextMarkerRangeForUIElementParameterizedAttribute = "AXTextMarkerRangeForUIElement" as CFString

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

private let caretObserverCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let tracker = Unmanaged<CaretTracker>.fromOpaque(refcon).takeUnretainedValue()
    tracker.handleAccessibilityNotification(notification as String, element: element)
}

final class CaretTracker {
    var onCaretPositionChanged: ((NSPoint?) -> Void)?

    private var timer: Timer?
    private var lastPosition: NSPoint?
    private var lastHadCaret = false
    private var lastLoggedApp = ""
    private var isAccessibilityTrusted = false
    private var didLogMissingAccessibilityPermission = false

    private var workspaceObserver: NSObjectProtocol?
    private var axObserver: AXObserver?
    private var observedAppPID: pid_t?
    private var observedAppElement: AXUIElement?
    private var observedFocusedElement: AXUIElement?

    func start() {
        guard timer == nil else { return }

        caretLog("start() called")

        let trusted = AXIsProcessTrusted()
        isAccessibilityTrusted = trusted
        caretLog("AXIsProcessTrusted = \(trusted)")

        if !trusted {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            caretLog("Requested accessibility permission")
        }

        installWorkspaceObserver()
        if trusted {
            attachObserverToFrontmostApp()
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }

        caretLog("Timer started")
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }

        detachObserver()

        if lastHadCaret {
            lastHadCaret = false
            lastPosition = nil
            onCaretPositionChanged?(nil)
        }
    }

    func dumpCurrentFocusContext() {
        refreshAccessibilityTrust()
        guard isAccessibilityTrusted else {
            caretLog("DEBUG: accessibility permission is not granted")
            return
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            caretLog("DEBUG: no frontmost application")
            return
        }

        let appName = frontApp.localizedName ?? "unknown"
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        caretLog("[\(appName)] DEBUG: begin focus dump")

        if let focusedElement = copyFocusedElement(from: appElement) {
            logElementSnapshot(appName: appName, label: "focused", element: focusedElement)

            if let resolvedElement = resolveCaretElement(startingAt: focusedElement),
               !CFEqual(resolvedElement, focusedElement) {
                logElementSnapshot(appName: appName, label: "resolved", element: resolvedElement)
            }

            for (index, ancestor) in ancestorElements(startingAt: focusedElement, maxDepth: 5).enumerated() {
                logElementSnapshot(appName: appName, label: "ancestor[\(index)]", element: ancestor)
            }

            let childCandidates = Array((focusedChildren(of: focusedElement) + nonFocusedChildren(of: focusedElement)).prefix(8))
            for (index, child) in childCandidates.enumerated() {
                logElementSnapshot(appName: appName, label: "child[\(index)]", element: child)
            }
        } else {
            caretLog("[\(appName)] DEBUG: no focused element")
        }

        caretLog("[\(appName)] DEBUG: end focus dump")
    }

    private func installWorkspaceObserver() {
        guard workspaceObserver == nil else { return }

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.attachObserverToFrontmostApp()
            self?.poll()
        }
    }

    private func attachObserverToFrontmostApp() {
        guard isAccessibilityTrusted else { return }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            detachObserver()
            return
        }

        let pid = frontApp.processIdentifier
        if pid == observedAppPID, axObserver != nil {
            refreshFocusedElementObservation()
            return
        }

        detachObserver()

        let appElement = AXUIElementCreateApplication(pid)
        observedAppPID = pid
        observedAppElement = appElement

        var observer: AXObserver?
        let result = AXObserverCreate(pid, caretObserverCallback, &observer)
        guard result == .success, let observer else {
            caretLog("[\(frontApp.localizedName ?? "unknown")] FAIL: observer error=\(result.rawValue)")
            return
        }

        axObserver = observer
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)

        registerAppNotification(kAXFocusedUIElementChangedNotification as CFString, element: appElement)
        registerAppNotification(kAXFocusedWindowChangedNotification as CFString, element: appElement)
        registerAppNotification(kAXSelectedTextChangedNotification as CFString, element: appElement)

        refreshFocusedElementObservation()
    }

    private func detachObserver() {
        unregisterFocusedElementNotifications()

        if let axObserver, let appElement = observedAppElement {
            unregisterNotification(kAXFocusedUIElementChangedNotification as CFString, element: appElement)
            unregisterNotification(kAXFocusedWindowChangedNotification as CFString, element: appElement)
            unregisterNotification(kAXSelectedTextChangedNotification as CFString, element: appElement)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes)
        }

        axObserver = nil
        observedAppPID = nil
        observedAppElement = nil
    }

    private func refreshFocusedElementObservation() {
        guard let appElement = observedAppElement else { return }
        guard let focusedElement = copyFocusedElement(from: appElement) else {
            unregisterFocusedElementNotifications()
            return
        }

        if let observedFocusedElement, CFEqual(observedFocusedElement, focusedElement) {
            return
        }

        unregisterFocusedElementNotifications()
        observedFocusedElement = focusedElement

        registerAppNotification(kAXSelectedTextChangedNotification as CFString, element: focusedElement)
        registerAppNotification(kAXValueChangedNotification as CFString, element: focusedElement)
        registerAppNotification(kAXLayoutChangedNotification as CFString, element: focusedElement)
    }

    private func unregisterFocusedElementNotifications() {
        guard let element = observedFocusedElement else { return }

        unregisterNotification(kAXSelectedTextChangedNotification as CFString, element: element)
        unregisterNotification(kAXValueChangedNotification as CFString, element: element)
        unregisterNotification(kAXLayoutChangedNotification as CFString, element: element)
        observedFocusedElement = nil
    }

    private func registerAppNotification(_ notification: CFString, element: AXUIElement) {
        guard let axObserver else { return }

        let result = AXObserverAddNotification(
            axObserver,
            element,
            notification,
            Unmanaged.passUnretained(self).toOpaque()
        )

        let ignoredResults: Set<AXError> = [.success, .notificationAlreadyRegistered, .notificationUnsupported, .illegalArgument]
        if !ignoredResults.contains(result) {
            caretLog("Observer add failed notification=\(notification) error=\(result.rawValue)")
        }
    }

    private func unregisterNotification(_ notification: CFString, element: AXUIElement) {
        guard let axObserver else { return }
        _ = AXObserverRemoveNotification(axObserver, element, notification)
    }

    fileprivate func handleAccessibilityNotification(_ notification: String, element: AXUIElement) {
        let focusedChanged = notification == (kAXFocusedUIElementChangedNotification as String)
            || notification == (kAXFocusedWindowChangedNotification as String)

        if focusedChanged {
            refreshFocusedElementObservation()
        } else if let observedFocusedElement, !CFEqual(observedFocusedElement, element) {
            refreshFocusedElementObservation()
        }

        poll()
    }

    private func poll() {
        refreshAccessibilityTrust()
        guard isAccessibilityTrusted else { return }

        attachObserverToFrontmostApp()

        let position = queryCaretPosition()
        let hasCaret = position != nil

        if position != lastPosition || hasCaret != lastHadCaret {
            lastPosition = position
            lastHadCaret = hasCaret
            onCaretPositionChanged?(position)
        }
    }

    private func refreshAccessibilityTrust() {
        let trusted = AXIsProcessTrusted()
        if trusted == isAccessibilityTrusted {
            return
        }

        isAccessibilityTrusted = trusted

        if trusted {
            didLogMissingAccessibilityPermission = false
            caretLog("Accessibility permission granted")
            attachObserverToFrontmostApp()
            return
        }

        detachObserver()
        if lastHadCaret {
            lastHadCaret = false
            lastPosition = nil
            onCaretPositionChanged?(nil)
        }

        if !didLogMissingAccessibilityPermission {
            caretLog("Accessibility permission missing; waiting for trust")
            didLogMissingAccessibilityPermission = true
        }
    }

    private func queryCaretPosition() -> NSPoint? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appName = frontApp.localizedName ?? "unknown"
        let pid = frontApp.processIdentifier
        let appElement = observedAppPID == pid ? (observedAppElement ?? AXUIElementCreateApplication(pid)) : AXUIElementCreateApplication(pid)

        guard let focusedElement = copyFocusedElement(from: appElement) else {
            logFocusFailure(appName: appName)
            return nil
        }

        let element = resolveCaretElement(startingAt: focusedElement) ?? focusedElement

        guard let caretRect = queryCaretRect(for: element, appName: appName),
              caretRect.size.height > 0,
              caretRect.origin.x.isFinite,
              caretRect.origin.y.isFinite else {
            logCaretFailure(appName: appName, element: element)
            return nil
        }

        if appName != lastLoggedApp {
            caretLog("[\(appName)] OK")
            lastLoggedApp = appName
        }

        return appKitPoint(for: caretRect)
    }

    private func queryCaretRect(for element: AXUIElement, appName: String) -> CGRect? {
        if let rect = directCaretRect(for: element) {
            return rect
        }

        if let rect = boundsForAncestorRangeContext(for: element) {
            return rect
        }

        if let rect = boundsForAncestorTextMarkerContext(for: element) {
            return rect
        }

        if let rect = approximateCaretRect(for: element) {
            return rect
        }

        if appName != lastLoggedApp {
            let role = stringAttribute(kAXRoleAttribute as CFString, from: element) ?? "unknown"
            let attrs = supportedAttributesSummary(for: element)
            let params = supportedParameterizedAttributesSummary(for: element)
            caretLog("[\(appName)] FAIL: no caret bounds role=\(role) attrs=\(attrs) params=\(params)")
            lastLoggedApp = appName
        }

        return nil
    }

    private func directCaretRect(for element: AXUIElement) -> CGRect? {
        if let rect = boundsForSelectedTextRange(element: element) {
            return rect
        }

        return boundsForSelectedTextMarkerRange(element: element)
    }

    private func boundsForSelectedTextRange(element: AXUIElement) -> CGRect? {
        let (result, value) = copyAttributeValue(kAXSelectedTextRangeAttribute as CFString, from: element)
        guard result == .success, let value, let range = decodeCFRange(value) else {
            return nil
        }

        if let rect = boundsForRange(element: element, rangeValue: value) {
            return rect
        }

        guard range.length == 0 else { return nil }

        if let rect = boundsForSingleCharacter(element: element, location: range.location) {
            return CGRect(x: rect.origin.x, y: rect.origin.y, width: 0, height: rect.height)
        }

        if range.location > 0, let rect = boundsForSingleCharacter(element: element, location: range.location - 1) {
            return CGRect(x: rect.maxX, y: rect.origin.y, width: 0, height: rect.height)
        }

        return nil
    }

    private func boundsForSelectedTextMarkerRange(element: AXUIElement) -> CGRect? {
        if let rect = boundsForTextMarkerAttribute(
            named: axSelectedTextMarkerRangeAttribute,
            element: element
        ) {
            return rect
        }

        return boundsForTextMarkerAttribute(
            named: axTextInputMarkedTextMarkerRangeAttribute,
            element: element
        )
    }

    private func boundsForTextMarkerAttribute(named attribute: CFString, element: AXUIElement) -> CGRect? {
        let (result, value) = copyAttributeValue(attribute, from: element)
        guard result == .success, let value else {
            return nil
        }

        return boundsForTextMarkerRange(element: element, markerRangeValue: value)
    }

    private func boundsForSingleCharacter(element: AXUIElement, location: CFIndex) -> CGRect? {
        var range = CFRange(location: location, length: 1)
        guard let value = AXValueCreate(.cfRange, &range) else {
            return nil
        }

        return boundsForRange(element: element, rangeValue: value)
    }

    private func boundsForRange(element: AXUIElement, rangeValue: CFTypeRef) -> CGRect? {
        guard let boundsValue = copyParameterizedAttributeValue(
            kAXBoundsForRangeParameterizedAttribute as CFString,
            from: element,
            parameter: rangeValue
        ) else {
            return nil
        }

        return decodeCGRect(boundsValue)
    }

    private func boundsForTextMarkerRange(element: AXUIElement, markerRangeValue: CFTypeRef) -> CGRect? {
        guard let boundsValue = copyParameterizedAttributeValue(
            axBoundsForTextMarkerRangeParameterizedAttribute,
            from: element,
            parameter: markerRangeValue
        ) else {
            return nil
        }

        return decodeCGRect(boundsValue)
    }

    private func boundsForAncestorRangeContext(for element: AXUIElement) -> CGRect? {
        let (result, rangeValue) = copyAttributeValue(kAXSelectedTextRangeAttribute as CFString, from: element)
        guard result == .success, let rangeValue else {
            return nil
        }

        for ancestor in ancestorElements(startingAt: element, maxDepth: 8) {
            let params = copyParameterizedAttributeNames(for: ancestor)
            guard params.contains(kAXBoundsForRangeParameterizedAttribute as String) else {
                continue
            }

            if let rect = boundsForRange(element: ancestor, rangeValue: rangeValue) {
                return rect
            }
        }

        return nil
    }

    private func boundsForAncestorTextMarkerContext(for element: AXUIElement) -> CGRect? {
        for ancestor in ancestorElements(startingAt: element, maxDepth: 8) {
            let params = copyParameterizedAttributeNames(for: ancestor)
            guard params.contains(axTextMarkerRangeForUIElementParameterizedAttribute as String),
                  params.contains(axBoundsForTextMarkerRangeParameterizedAttribute as String) else {
                continue
            }

            guard let markerRangeValue = copyParameterizedAttributeValue(
                axTextMarkerRangeForUIElementParameterizedAttribute,
                from: ancestor,
                parameter: element
            ) else {
                continue
            }

            if let rect = boundsForTextMarkerRange(element: ancestor, markerRangeValue: markerRangeValue) {
                return rect
            }
        }

        return nil
    }

    private func approximateCaretRect(for element: AXUIElement) -> CGRect? {
        for candidate in [element] + ancestorElements(startingAt: element, maxDepth: 4) {
            guard let frame = frameOfElement(candidate),
                  frame.width > 0,
                  frame.height > 0 else {
                continue
            }

            let insetX = min(max(frame.width * 0.03, 10), 24)
            let insetY = min(max(frame.height * 0.12, 2), 8)
            let caretHeight = min(max(frame.height - (insetY * 2), 14), 28)

            return CGRect(
                x: frame.minX + insetX,
                y: frame.minY + insetY,
                width: 0,
                height: caretHeight
            )
        }

        return nil
    }

    private func copyFocusedElement(from appElement: AXUIElement) -> AXUIElement? {
        if let element = copyAXElementAttribute(kAXFocusedUIElementAttribute as CFString, from: appElement) {
            return element
        }

        let systemWide = AXUIElementCreateSystemWide()
        if let element = copyAXElementAttribute(kAXFocusedUIElementAttribute as CFString, from: systemWide) {
            return element
        }

        guard let window = copyAXElementAttribute(kAXFocusedWindowAttribute as CFString, from: appElement) else {
            return nil
        }

        if let element = copyAXElementAttribute(kAXFocusedUIElementAttribute as CFString, from: window) {
            return element
        }

        return findFocusedDescendant(in: window, depth: 0)
    }

    private func ancestorElements(startingAt element: AXUIElement, maxDepth: Int) -> [AXUIElement] {
        var ancestors: [AXUIElement] = []
        var currentElement = copyAXElementAttribute(kAXParentAttribute as CFString, from: element)
        var depth = 0
        var seen = Set<String>()

        while let current = currentElement, depth < maxDepth {
            let key = "\(Unmanaged.passUnretained(current).toOpaque())"
            if !seen.insert(key).inserted {
                break
            }

            ancestors.append(current)
            currentElement = copyAXElementAttribute(kAXParentAttribute as CFString, from: current)
            depth += 1
        }

        return ancestors
    }

    private func resolveCaretElement(startingAt element: AXUIElement) -> AXUIElement? {
        let currentScore = caretSupportScore(for: element)
        let descendant = findBestCaretCandidate(in: element, depth: 0)
        let descendantScore = descendant.map { caretSupportScore(for: $0) } ?? 0

        if descendantScore > currentScore {
            return descendant
        }

        if currentScore > 0 {
            return element
        }

        return descendant
    }

    private func findFocusedDescendant(in root: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 8 else { return nil }

        let prioritizedChildren = focusedChildren(of: root) + nonFocusedChildren(of: root)
        for child in prioritizedChildren {
            if elementSupportsCaretTracking(child) {
                return child
            }
        }

        for child in prioritizedChildren {
            if let descendant = findFocusedDescendant(in: child, depth: depth + 1) {
                return descendant
            }
        }

        return nil
    }

    private func findBestCaretCandidate(in root: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 8 else { return nil }

        var bestElement: AXUIElement?
        var bestScore = 0
        let children = focusedChildren(of: root) + nonFocusedChildren(of: root)

        for child in children {
            let score = caretSupportScore(for: child)
            if score > bestScore {
                bestElement = child
                bestScore = score
            }

            if let descendant = findBestCaretCandidate(in: child, depth: depth + 1) {
                let descendantScore = caretSupportScore(for: descendant)
                if descendantScore > bestScore {
                    bestElement = descendant
                    bestScore = descendantScore
                }
            }
        }

        return bestElement
    }

    private func elementSupportsCaretTracking(_ element: AXUIElement) -> Bool {
        caretSupportScore(for: element) > 0
    }

    private func caretSupportScore(for element: AXUIElement) -> Int {
        let attrs = copyAttributeNames(for: element)
        let params = copyParameterizedAttributeNames(for: element)

        let hasBounds = params.contains(kAXBoundsForRangeParameterizedAttribute as String)
            || params.contains(axBoundsForTextMarkerRangeParameterizedAttribute as String)
        if hasBounds {
            return 3
        }

        let hasTextMarkers = attrs.contains(axSelectedTextMarkerRangeAttribute as String)
            || attrs.contains(axTextInputMarkedTextMarkerRangeAttribute as String)
        if hasTextMarkers {
            return 2
        }

        if attrs.contains(kAXSelectedTextRangeAttribute as String) {
            return 1
        }

        return 0
    }

    private func focusedChildren(of element: AXUIElement) -> [AXUIElement] {
        childElements(of: element).filter { boolAttribute(kAXFocusedAttribute as CFString, from: $0) == true }
    }

    private func nonFocusedChildren(of element: AXUIElement) -> [AXUIElement] {
        childElements(of: element).filter { boolAttribute(kAXFocusedAttribute as CFString, from: $0) != true }
    }

    private func childElements(of element: AXUIElement) -> [AXUIElement] {
        var seen = Set<String>()
        var result: [AXUIElement] = []

        for attribute in [kAXSelectedChildrenAttribute as CFString, kAXChildrenAttribute as CFString] {
            for child in copyAXElementArrayAttribute(attribute, from: element) {
                let key = "\(Unmanaged.passUnretained(child).toOpaque())"
                if seen.insert(key).inserted {
                    result.append(child)
                }
            }
        }

        return result
    }

    private func copyAXElementAttribute(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        let (result, value) = copyAttributeValue(attribute, from: element)
        guard result == .success, let value else {
            return nil
        }

        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func copyAXElementArrayAttribute(_ attribute: CFString, from element: AXUIElement) -> [AXUIElement] {
        let (result, value) = copyAttributeValue(attribute, from: element)
        guard result == .success, let value, let array = value as? [Any] else {
            return []
        }

        return array.compactMap { item in
            guard CFGetTypeID(item as CFTypeRef) == AXUIElementGetTypeID() else {
                return nil
            }
            return unsafeBitCast(item as CFTypeRef, to: AXUIElement.self)
        }
    }

    private func copyAttributeValue(_ attribute: CFString, from element: AXUIElement) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        return (result, value)
    }

    private func copyParameterizedAttributeValue(
        _ attribute: CFString,
        from element: AXUIElement,
        parameter: CFTypeRef
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(element, attribute, parameter, &value)
        guard result == .success else {
            return nil
        }
        return value
    }

    private func decodeCFRange(_ value: CFTypeRef) -> CFRange? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }

        return range
    }

    private func decodeCGRect(_ value: CFTypeRef) -> CGRect? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgRect else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect), rect.height > 0 else {
            return nil
        }

        return rect
    }

    private func decodeCGPoint(_ value: CFTypeRef) -> CGPoint? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func decodeCGSize(_ value: CFTypeRef) -> CGSize? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        let (result, value) = copyAttributeValue(attribute, from: element)
        guard result == .success, let value else {
            return nil
        }

        return value as? String
    }

    private func boolAttribute(_ attribute: CFString, from element: AXUIElement) -> Bool? {
        let (result, value) = copyAttributeValue(attribute, from: element)
        guard result == .success, let value else {
            return nil
        }

        return value as? Bool
    }

    private func frameOfElement(_ element: AXUIElement) -> CGRect? {
        let (positionResult, positionValue) = copyAttributeValue(kAXPositionAttribute as CFString, from: element)
        let (sizeResult, sizeValue) = copyAttributeValue(kAXSizeAttribute as CFString, from: element)

        guard positionResult == .success,
              sizeResult == .success,
              let positionValue,
              let sizeValue,
              let origin = decodeCGPoint(positionValue),
              let size = decodeCGSize(sizeValue) else {
            return nil
        }

        return CGRect(origin: origin, size: size)
    }

    private func appKitPoint(for axRect: CGRect) -> NSPoint? {
        guard let desktopBounds = desktopBounds() else {
            return nil
        }

        let appKitY = desktopBounds.maxY - axRect.origin.y
        return NSPoint(x: axRect.origin.x, y: appKitY)
    }

    private func desktopBounds() -> CGRect? {
        let frames = NSScreen.screens.map(\.frame)
        guard var bounds = frames.first else {
            return nil
        }

        for frame in frames.dropFirst() {
            bounds = bounds.union(frame)
        }

        return bounds
    }

    private func supportedAttributesSummary(for element: AXUIElement) -> String {
        let names = copyAttributeNames(for: element)
        let interesting = [
            kAXSelectedTextRangeAttribute as String,
            kAXVisibleCharacterRangeAttribute as String,
            axSelectedTextMarkerRangeAttribute as String,
            axTextInputMarkedTextMarkerRangeAttribute as String,
            kAXPositionAttribute as String,
            kAXSizeAttribute as String,
        ]

        let summary = interesting.filter { names.contains($0) }
        return summary.isEmpty ? "-" : summary.joined(separator: ",")
    }

    private func supportedParameterizedAttributesSummary(for element: AXUIElement) -> String {
        let names = copyParameterizedAttributeNames(for: element)
        let interesting = [
            kAXBoundsForRangeParameterizedAttribute as String,
            axBoundsForTextMarkerRangeParameterizedAttribute as String,
            axTextMarkerRangeForUIElementParameterizedAttribute as String,
        ]

        let summary = interesting.filter { names.contains($0) }
        return summary.isEmpty ? "-" : summary.joined(separator: ",")
    }

    private func copyAttributeNames(for element: AXUIElement) -> Set<String> {
        var value: CFArray?
        guard AXUIElementCopyAttributeNames(element, &value) == .success,
              let names = value as? [String] else {
            return []
        }

        return Set(names)
    }

    private func copyParameterizedAttributeNames(for element: AXUIElement) -> Set<String> {
        var value: CFArray?
        guard AXUIElementCopyParameterizedAttributeNames(element, &value) == .success,
              let names = value as? [String] else {
            return []
        }

        return Set(names)
    }

    private func logFocusFailure(appName: String) {
        guard appName != lastLoggedApp else { return }
        caretLog("[\(appName)] FAIL: no focused element")
        lastLoggedApp = appName
    }

    private func logCaretFailure(appName: String, element: AXUIElement) {
        guard appName != lastLoggedApp else { return }
        let role = stringAttribute(kAXRoleAttribute as CFString, from: element) ?? "unknown"
        caretLog("[\(appName)] FAIL: caret rect unavailable role=\(role)")
        lastLoggedApp = appName
    }

    private func logElementSnapshot(appName: String, label: String, element: AXUIElement) {
        let role = stringAttribute(kAXRoleAttribute as CFString, from: element) ?? "unknown"
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: element) ?? "-"
        let title = stringAttribute(kAXTitleAttribute as CFString, from: element) ?? "-"
        let attrs = supportedAttributesSummary(for: element)
        let params = supportedParameterizedAttributesSummary(for: element)

        var parts = [
            "[\(appName)] DEBUG: \(label)",
            "role=\(role)",
            "subrole=\(subrole)",
            "title=\(title)",
            "attrs=\(attrs)",
            "params=\(params)",
            "score=\(caretSupportScore(for: element))",
        ]

        if let frame = frameOfElement(element) {
            parts.append("frame=\(NSStringFromRect(frame))")
        }

        caretLog(parts.joined(separator: " "))
    }
}
