import Carbon
import Cocoa

class InputSourceManager {
    var onInputSourceChanged: ((Bool) -> Void)?

    private let notificationName = NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged")

    init() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceDidChange),
            name: notificationName,
            object: nil
        )
    }

    func isCurrentInputSourceKorean() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return false
        }

        // Check input source ID for Korean
        if let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let sourceID = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            if sourceID.lowercased().contains("korean") {
                return true
            }
        }

        // Fallback: check languages array
        if let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
            let languages = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as! [String]
            if languages.contains("ko") {
                return true
            }
        }

        return false
    }

    @objc private func inputSourceDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let isKorean = self.isCurrentInputSourceKorean()
            self.onInputSourceChanged?(isKorean)
        }
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }
}
