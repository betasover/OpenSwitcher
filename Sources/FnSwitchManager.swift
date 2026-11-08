import Foundation
import IOKit.hid
import AppKit
import Carbon
import os.log

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
        // Match all devices so we do not accidentally filter out Apple Internal Keyboard
        IOHIDManagerSetDeviceMatching(manager, nil)
        
        let elements: [[String: Int]] = [
            [kIOHIDElementUsagePageKey: fnPage, kIOHIDElementUsageKey: fnUsage],
            [kIOHIDElementUsagePageKey: 0x07],
        ]
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
        
        // If real keyboard key is pressed while Fn is down, mark as chord (e.g. Fn + Backspace, Fn + F-keys, Fn + arrows)
        // Only page 0x07 with usage >= 4 represents actual keys (avoiding false flags on consumer pages)
        if fnDown && pressed && page == 0x07 && usage >= 0x04 {
            chord = true
        }
    }
    
    func triggerInstantSwitch() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSwitchTime > 0.18 else { return }
        lastSwitchTime = now
        
        NSLog("OpenSwitcher: Instant Fn Switch triggered")
        LayoutManager.shared.toggleFast()
        SoundManager.shared.play()
    }
}
