import Foundation
import IOKit.hid
import AppKit
import Carbon

private let fnPage: Int = 0xFF
private let fnUsage: Int = 0x03
private let tapLimit: CFAbsoluteTime = 0.50

private let valueCallback: IOHIDValueCallback = { context, _, _, value in
    guard let context = context else { return }
    let element = IOHIDValueGetElement(value)
    let page = Int(IOHIDElementGetUsagePage(element))
    let usage = Int(IOHIDElementGetUsage(element))
    let pressed = IOHIDValueGetIntegerValue(value) != 0
    let manager = Unmanaged<FnSwitchManager>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        manager.handleValue(page: page, usage: usage, pressed: pressed)
    }
}

private let deviceCallback: IOHIDDeviceCallback = { context, _, _, _ in
    guard let context = context else { return }
    let manager = Unmanaged<FnSwitchManager>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        manager.handleDeviceChanged()
    }
}

@MainActor
final class FnSwitchManager: ObservableObject {
    static let shared = FnSwitchManager()
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "fastFnSwitch")
            applyConfiguration()
        }
    }
    
    private var hidManager: IOHIDManager?
    private var lastSwitchTime: CFAbsoluteTime = 0
    private var fnDown: Bool = false
    private var chord: Bool = false
    private var pressedAt: CFAbsoluteTime = 0
    
    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "fastFnSwitch")
        if isEnabled {
            applyConfiguration()
        }
    }
    
    func applyConfiguration() {
        if isEnabled {
            // Disable macOS native delay & popup overlay (set to Do Nothing)
            setAppleFnUsage(type: 0)
            startMonitoring()
        } else {
            // Restore macOS native behavior (type 1 = Change Input Source)
            stopMonitoring()
            setAppleFnUsage(type: 1)
        }
    }
    
    func restoreSystemDefaultsOnQuit() {
        if isEnabled {
            stopMonitoring()
            setAppleFnUsage(type: 1)
        }
    }
    
    private func setAppleFnUsage(type: Int) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = ["write", "com.apple.HIToolbox", "AppleFnUsageType", "-int", "\(type)"]
        try? p.run()
        p.waitUntilExit()
        
        let k = Process()
        k.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        k.arguments = ["TextInputMenuAgent"]
        try? k.run()
        k.waitUntilExit()
    }
    
    private func startMonitoring() {
        guard hidManager == nil else { return }
        
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let devices: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x06],
            [kIOHIDDeviceUsagePageKey: fnPage, kIOHIDDeviceUsageKey: fnUsage],
        ]
        let elements: [[String: Int]] = [
            [kIOHIDElementUsagePageKey: fnPage, kIOHIDElementUsageKey: fnUsage],
            [kIOHIDElementUsagePageKey: 0x07],
            [kIOHIDElementUsagePageKey: 0x0C],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, devices as CFArray)
        IOHIDManagerSetInputValueMatchingMultiple(manager, elements as CFArray)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, valueCallback, context)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceCallback, context)
        
        let openRes = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openRes == kIOReturnSuccess {
            self.hidManager = manager
        }
    }
    
    private func stopMonitoring() {
        guard let manager = hidManager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = nil
        fnDown = false
        chord = false
    }
    
    func handleDeviceChanged() {
        // Re-open if devices connected/disconnected (e.g. Magic Keyboard reconnect, sleep/wake)
        guard isEnabled, let manager = hidManager else { return }
        _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }
    
    func handleValue(page: Int, usage: Int, pressed: Bool) {
        guard isEnabled else { return }
        
        let now = CFAbsoluteTimeGetCurrent()
        
        // Auto-heal: If fnDown was stuck for more than 0.8s, force reset
        if fnDown && (now - pressedAt > 0.80) {
            fnDown = false
            chord = false
        }
        
        if page == fnPage && usage == fnUsage {
            if pressed {
                fnDown = true
                pressedAt = now
                let held = CGEventSource.flagsState(.combinedSessionState)
                    .intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
                chord = !held.isEmpty
            } else {
                let duration = now - pressedAt
                if fnDown && !chord && duration < tapLimit {
                    triggerInstantSwitch()
                }
                fnDown = false
                chord = false
            }
            return
        }
        
        // If other key is pressed while Fn is down, mark as chord (e.g. Fn + Backspace, Fn + F-keys)
        if fnDown && pressed {
            if page == 0x07 && (0x04...0xE7).contains(usage) {
                chord = true
            } else if page == 0x0C {
                chord = true
            }
        }
    }
    
    func triggerInstantSwitch() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSwitchTime > 0.18 else { return }
        lastSwitchTime = now
        
        LayoutManager.shared.toggleFast()
        SoundManager.shared.play()
    }
}
