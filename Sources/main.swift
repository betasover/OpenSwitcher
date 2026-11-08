import AppKit
import ApplicationServices

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // Runs as menu bar item without Dock icon

// Check accessibility permissions
let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
let isTrusted = AXIsProcessTrustedWithOptions(options)
if !isTrusted {
    print("OpenSwitcher: Accessibility permission required. Prompted user.")
}

let statusBar = StatusBarController()

if !EventTapManager.shared.start() {
    print("OpenSwitcher: Failed to start CGEventTap. Please grant Accessibility permissions in System Settings -> Privacy & Security -> Accessibility.")
} else {
    print("OpenSwitcher: EventTap successfully started.")
}

app.run()
