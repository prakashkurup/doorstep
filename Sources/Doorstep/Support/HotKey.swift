import AppKit
import Carbon.HIToolbox

/// ⌥⌘D opens or closes the panel from anywhere. Uses Carbon's hot key API, which needs
/// no Accessibility permission.
enum GlobalHotKey {
    private static var ref: EventHotKeyRef?

    static func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { GlobalHotKey.togglePanel() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4452_5354), id: 1) // "DRST"
        RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
    }

    /// SwiftUI has no API to open a MenuBarExtra, so click its status item button.
    @MainActor
    static func togglePanel() {
        for window in NSApp.windows where window.className.contains("StatusBarWindow") {
            if let button = findButton(in: window.contentView) {
                button.performClick(nil)
                return
            }
        }
    }

    private static func findButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for sub in view.subviews { if let found = findButton(in: sub) { return found } }
        return nil
    }
}
