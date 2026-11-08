@preconcurrency import CoreGraphics
@preconcurrency import ApplicationServices
import AppKit

@MainActor
final class EventTapManager {
    static let shared = EventTapManager()
    
    var autoSwitchEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "autoSwitch") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoSwitch") }
    }
    var doubleShiftEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "doubleShift") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "doubleShift") }
    }
    var doubleCapsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "doubleCaps") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "doubleCaps") }
    }
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?
    
    // Typing tracking
    private var currentWord: String = ""
    private var lastCompletedWord: String = ""
    private var lastTrailingDelimiter: String = ""
    private var isSimulating: Bool = false
    private var pendingEvents: [CGEvent] = []
    
    // Double Shift tracking
    private var shiftKeyDownTime: Date?
    private var lastShiftReleaseTime: Date?
    private var watchdogTimer: Timer?
    
    // Fn / Globe key tracking
    private var fnPressTime: Date?
    private var fnHasChord: Bool = false
    
    private init() {
        // Reset typing buffer when frontmost application changes
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.currentWord = ""
                self?.lastCompletedWord = ""
                self?.lastTrailingDelimiter = ""
                self?.shiftKeyDownTime = nil
                self?.lastShiftReleaseTime = nil
                self?.fnPressTime = nil
                self?.fnHasChord = false
            }
        }
    }
    
    func start() -> Bool {
        guard eventTap == nil else { return true }
        
        let mask = (1 << CGEventType.keyDown.rawValue) |
                   (1 << CGEventType.flagsChanged.rawValue) |
                   (1 << CGEventType.leftMouseDown.rawValue) |
                   (1 << CGEventType.rightMouseDown.rawValue)
        
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let refcon = refcon {
                    DispatchQueue.main.async {
                        let mgr = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                        mgr.enableTap()
                    }
                }
                return Unmanaged.passUnretained(event)
            }
            
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let mgr = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                return mgr.handle(proxy: proxy, type: type, event: event)
            }
        }
        
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        ) else {
            schedulePermissionPolling()
            return false
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        permissionTimer?.invalidate()
        permissionTimer = nil
        startWatchdog()
        return true
    }
    
    private func startWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let tap = self.eventTap else { return }
                if !CGEvent.tapIsEnabled(tap: tap) {
                    self.enableTap()
                }
            }
        }
    }
    
    private func schedulePermissionPolling() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                if AXIsProcessTrusted() {
                    if self?.start() == true {
                        self?.permissionTimer?.invalidate()
                        self?.permissionTimer = nil
                    }
                }
            }
        }
    }
    
    func stop() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }
    
    func enableTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    
    func disableTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }
    
    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if isSimulating {
            // Buffer user keystrokes during retyping to prevent collision / double letters
            if type == .keyDown {
                if let cp = event.copy() {
                    pendingEvents.append(cp)
                }
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
        
        // Mouse click moves text cursor -> reset word buffer & pending shifts
        if type == .leftMouseDown || type == .rightMouseDown {
            currentWord = ""
            lastCompletedWord = ""
            lastTrailingDelimiter = ""
            shiftKeyDownTime = nil
            lastShiftReleaseTime = nil
            fnPressTime = nil
            fnHasChord = false
            return Unmanaged.passUnretained(event)
        }
        
        if type == .flagsChanged {
            handleFlagsChanged(event: event)
            return Unmanaged.passUnretained(event)
        }
        
        if type == .keyDown {
            // Any key pressed cancels solitary Shift tap and marks Fn chord
            shiftKeyDownTime = nil
            lastShiftReleaseTime = nil
            if fnPressTime != nil {
                fnHasChord = true
            }
            handleKeyDown(event: event)
            return Unmanaged.passUnretained(event)
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func handleFlagsChanged(event: CGEvent) {
        let flags = event.flags
        
        // Instant Fn / Globe key handling
        if FnSwitchManager.shared.isEnabled {
            let isFnDown = flags.contains(.maskSecondaryFn)
            if isFnDown {
                if fnPressTime == nil {
                    fnPressTime = Date()
                    let otherMods = flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
                    fnHasChord = !otherMods.isEmpty
                }
            } else if let downTime = fnPressTime {
                let duration = Date().timeIntervalSince(downTime)
                fnPressTime = nil
                if !fnHasChord && duration < 0.50 {
                    FnSwitchManager.shared.triggerInstantSwitch()
                }
                fnHasChord = false
            }
        }
        
        guard doubleShiftEnabled else { return }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        // 0x38 = Left Shift, 0x3C = Right Shift
        guard keyCode == 0x38 || keyCode == 0x3C else {
            // Other modifier pressed (Cmd, Opt, Ctrl, Caps Lock, Fn) -> cancel Double Shift
            shiftKeyDownTime = nil
            lastShiftReleaseTime = nil
            return
        }
        
        let isShiftDown = flags.contains(.maskShift)
        let now = Date()
        
        if isShiftDown {
            shiftKeyDownTime = now
        } else {
            // Shift was released
            if let downTime = shiftKeyDownTime {
                let pressDuration = now.timeIntervalSince(downTime)
                shiftKeyDownTime = nil
                
                // Only a quick tap (< 300ms) with NO other key pressed counts
                if pressDuration < 0.30 {
                    if let lastRelease = lastShiftReleaseTime, now.timeIntervalSince(lastRelease) < 0.35 {
                        // Double Shift detected!
                        lastShiftReleaseTime = nil
                        DispatchQueue.main.async { [weak self] in
                            self?.switchLastWordOrSelection()
                        }
                    } else {
                        lastShiftReleaseTime = now
                    }
                } else {
                    lastShiftReleaseTime = nil
                }
            } else {
                lastShiftReleaseTime = nil
            }
        }
    }
    
    private func handleKeyDown(event: CGEvent) {
        let flags = event.flags
        // Ignore key combos with Command / Control
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            currentWord = ""
            lastCompletedWord = ""
            lastTrailingDelimiter = ""
            return
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // Backspace
        if keyCode == 0x33 {
            if !currentWord.isEmpty {
                currentWord.removeLast()
            } else if !lastTrailingDelimiter.isEmpty {
                lastTrailingDelimiter.removeLast()
                if lastTrailingDelimiter.isEmpty && !lastCompletedWord.isEmpty {
                    currentWord = lastCompletedWord
                    lastCompletedWord = ""
                }
            } else {
                lastCompletedWord = ""
            }
            return
        }
        
        // Escape
        if keyCode == 0x35 {
            currentWord = ""
            lastCompletedWord = ""
            lastTrailingDelimiter = ""
            return
        }
        
        // Arrow keys (0x7B=Left, 0x7C=Right, 0x7D=Down, 0x7E=Up) & Home (0x73), End (0x77), PgUp (0x74), PgDn (0x79)
        if (0x7B...0x7E).contains(keyCode) || keyCode == 0x73 || keyCode == 0x77 || keyCode == 0x74 || keyCode == 0x79 {
            currentWord = ""
            lastCompletedWord = ""
            lastTrailingDelimiter = ""
            return
        }
        
        // Word delimiters: Space (0x31), Return (0x24), Tab (0x30)
        if keyCode == 0x31 || keyCode == 0x24 || keyCode == 0x30 {
            let delim = (keyCode == 0x31 ? " " : (keyCode == 0x24 ? "\n" : "\t"))
            if !currentWord.isEmpty {
                lastCompletedWord = currentWord
                lastTrailingDelimiter = delim
                let wordToCheck = currentWord
                currentWord = ""
                
                if autoSwitchEnabled && !AppExceptions.shared.isFrontmostAppIgnored() {
                    let trailing = delim
                    
                    // Double Caps check: ПРивет -> Привет
                    if doubleCapsEnabled, let fixedCaps = LanguageDetector.detectDoubleCaps(word: wordToCheck) {
                        DispatchQueue.main.async { [weak self] in
                            self?.fixDoubleCaps(word: wordToCheck, fixed: fixedCaps, trailingKey: trailing)
                        }
                    } else if let targetLang = LanguageDetector.detectMismatch(word: wordToCheck) {
                        DispatchQueue.main.async { [weak self] in
                            self?.autoReplace(word: wordToCheck, targetLanguage: targetLang, trailingKey: trailing)
                        }
                    }
                }
            } else if !lastCompletedWord.isEmpty {
                lastTrailingDelimiter.append(delim)
            }
            return
        }
        
        // Extract Unicode char
        var length: Int = 0
        event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        if length > 0 {
            var buffer = [UniChar](repeating: 0, count: length)
            event.keyboardGetUnicodeString(maxStringLength: length, actualStringLength: &length, unicodeString: &buffer)
            let str = String(utf16CodeUnits: buffer, count: length)
            
            // Punctuation delimiters: . , ! ? ; : ( ) \n \t
            let delimiters: Set<Character> = [".", ",", "!", "?", ";", ":", "(", ")", "\n", "\t"]
            if let first = str.first, delimiters.contains(first) {
                if !currentWord.isEmpty {
                    lastCompletedWord = currentWord
                    lastTrailingDelimiter = str
                    let wordToCheck = currentWord
                    currentWord = ""
                    
                    if autoSwitchEnabled && !AppExceptions.shared.isFrontmostAppIgnored() {
                        if doubleCapsEnabled, let fixedCaps = LanguageDetector.detectDoubleCaps(word: wordToCheck) {
                            DispatchQueue.main.async { [weak self] in
                                self?.fixDoubleCaps(word: wordToCheck, fixed: fixedCaps, trailingKey: str)
                            }
                        } else if let targetLang = LanguageDetector.detectMismatch(word: wordToCheck) {
                            DispatchQueue.main.async { [weak self] in
                                self?.autoReplace(word: wordToCheck, targetLanguage: targetLang, trailingKey: str)
                            }
                        }
                    }
                } else if !lastCompletedWord.isEmpty {
                    lastTrailingDelimiter.append(str)
                }
            } else {
                currentWord.append(str)
                lastTrailingDelimiter = ""
            }
        }
    }
    
    private func autoReplace(word: String, targetLanguage: LayoutManager.Language, trailingKey: String) {
        guard !word.isEmpty else { return }
        let converted = KeyboardMapper.shared.convert(word, to: targetLanguage)
        let convertedTrailing = trailingKey.isEmpty ? "" : KeyboardMapper.shared.convert(trailingKey, to: targetLanguage)
        
        isSimulating = true
        
        // 1. Switch system layout
        LayoutManager.shared.switchTo(targetLanguage)
        usleep(20_000)
        
        // 2. Delete the word and trailing character
        let deleteCount = word.count + (trailingKey.isEmpty ? 0 : trailingKey.count)
        sendBackspace(count: deleteCount)
        usleep(20_000)
        
        // 3. Type converted word + trailing in fast chunks
        sendString(converted + convertedTrailing)
        playSound()
        
        isSimulating = false
        flushPendingEvents()
        
        lastCompletedWord = converted
        lastTrailingDelimiter = convertedTrailing
    }
    
    private func fixDoubleCaps(word: String, fixed: String, trailingKey: String) {
        isSimulating = true
        
        let deleteCount = word.count + (trailingKey.isEmpty ? 0 : trailingKey.count)
        sendBackspace(count: deleteCount)
        usleep(20_000)
        sendString(fixed + trailingKey)
        playSound()
        
        isSimulating = false
        flushPendingEvents()
        
        lastCompletedWord = fixed
        lastTrailingDelimiter = trailingKey
    }
    
    func switchLastWordOrSelection() {
        // 1. Try Accessibility selection first (safe: only if text IS selected)
        if replaceAccessibilitySelection() {
            playSound()
            return
        }
        
        // 2. Fallback: replace current word or last completed word
        let hadTrailing = currentWord.isEmpty && !lastCompletedWord.isEmpty
        let trailing = hadTrailing ? lastTrailingDelimiter : ""
        let targetWord = currentWord.isEmpty ? lastCompletedWord : currentWord
        guard !targetWord.isEmpty else {
            LayoutManager.shared.toggle()
            playSound()
            return
        }
        
        let targetLang: LayoutManager.Language
        if targetWord.contains(where: { ("\u{0400}"..."\u{04FF}").contains($0) }) {
            targetLang = .english
        } else {
            targetLang = .russian
        }
        
        let converted = KeyboardMapper.shared.convert(targetWord, to: targetLang)
        let convertedTrailing = trailing.isEmpty ? "" : KeyboardMapper.shared.convert(trailing, to: targetLang)
        let deleteCount = targetWord.count + trailing.count
        
        isSimulating = true
        LayoutManager.shared.switchTo(targetLang)
        usleep(20_000)
        sendBackspace(count: deleteCount)
        usleep(20_000)
        sendString(converted + convertedTrailing)
        playSound()
        
        isSimulating = false
        flushPendingEvents()
        
        if hadTrailing {
            currentWord = ""
            lastCompletedWord = converted
            lastTrailingDelimiter = convertedTrailing
        } else {
            currentWord = converted
            lastCompletedWord = ""
            lastTrailingDelimiter = ""
        }
        UserDictionary.shared.learn(converted)
    }
    
    private func replaceAccessibilitySelection() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement as! AXUIElement? else {
            return false
        }
        
        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedValue) == .success,
              let selectedString = selectedValue as? String, !selectedString.isEmpty else {
            return false
        }
        
        let targetLang: LayoutManager.Language
        if selectedString.contains(where: { ("\u{0400}"..."\u{04FF}").contains($0) }) {
            targetLang = .english
        } else {
            targetLang = .russian
        }
        
        let converted = KeyboardMapper.shared.convert(selectedString, to: targetLang)
        
        // Try direct Accessibility attribute setter
        if AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, converted as CFTypeRef) == .success {
            LayoutManager.shared.switchTo(targetLang)
            UserDictionary.shared.learn(converted)
            return true
        }
        
        // If setter not supported (e.g. web views, Slack), paste over known selection
        let pasteboard = NSPasteboard.general
        let oldString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(converted, forType: .string)
        
        LayoutManager.shared.switchTo(targetLang)
        usleep(20_000)
        simulateKeyCombo(virtualKey: 0x09, flags: .maskCommand) // 'v'
        UserDictionary.shared.learn(converted)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let old = oldString {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }
        return true
    }
    
    private func simulateKeyCombo(virtualKey: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cgSessionEventTap)
        usleep(1_500)
        up.post(tap: .cgSessionEventTap)
    }
    
    private func playSound() {
        SoundManager.shared.play()
    }
    
    private func sendBackspace(count: Int) {
        guard count > 0 else { return }
        let src = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<count {
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0x33, keyDown: true),
                  let up = CGEvent(keyboardEventSource: src, virtualKey: 0x33, keyDown: false) else { continue }
            
            down.flags = []
            up.flags = []
            down.post(tap: .cgSessionEventTap)
            usleep(1_500)
            up.post(tap: .cgSessionEventTap)
            usleep(3_500)
        }
    }
    
    private func sendString(_ text: String) {
        guard !text.isEmpty else { return }
        let src = CGEventSource(stateID: .hidSystemState)
        
        let utf16Array = Array(text.utf16)
        let chunkSize = 20
        var index = 0
        
        while index < utf16Array.count {
            let count = min(chunkSize, utf16Array.count - index)
            var chunk = Array(utf16Array[index..<(index + count)])
            
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) else { break }
            
            down.flags = []
            up.flags = []
            down.keyboardSetUnicodeString(stringLength: count, unicodeString: &chunk)
            up.keyboardSetUnicodeString(stringLength: count, unicodeString: &chunk)
            
            down.post(tap: .cgSessionEventTap)
            usleep(1_500)
            up.post(tap: .cgSessionEventTap)
            usleep(3_500)
            
            index += count
        }
    }
    
    private func flushPendingEvents() {
        guard !pendingEvents.isEmpty else { return }
        let events = pendingEvents
        pendingEvents.removeAll()
        for ev in events {
            ev.post(tap: .cgSessionEventTap)
            usleep(2_000)
        }
    }
}
