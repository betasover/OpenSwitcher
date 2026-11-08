@preconcurrency import Carbon
import AppKit

@MainActor
final class LayoutManager {
    static let shared = LayoutManager()
    
    enum Language: String {
        case english = "EN"
        case russian = "RU"
        case other = "??"
        
        var opposite: Language {
            switch self {
            case .english: return .russian
            case .russian: return .english
            case .other: return .english
            }
        }
    }
    
    private(set) var englishSource: TISInputSource?
    private(set) var russianSource: TISInputSource?
    private var lastSwitchTime: CFAbsoluteTime = 0
    private var lastTargetLanguage: Language?
    
    init() {
        refreshSources()
        let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        DistributedNotificationCenter.default().addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let cur = self.currentLanguage()
                if cur != .other {
                    self.lastTargetLanguage = cur
                }
            }
        }
    }
    
    func refreshSources() {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { return }
        for src in list {
            guard let cat = TISGetInputSourceProperty(src, kTISPropertyInputSourceCategory) else { continue }
            let catStr = Unmanaged<CFString>.fromOpaque(cat).takeUnretainedValue() as String
            guard catStr == (kTISCategoryKeyboardInputSource as String) else { continue }
            
            guard let isSelectable = TISGetInputSourceProperty(src, kTISPropertyInputSourceIsSelectCapable) else { continue }
            let canSelect = Unmanaged<CFBoolean>.fromOpaque(isSelectable).takeUnretainedValue()
            guard CFBooleanGetValue(canSelect) else { continue }
            
            if let idPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) {
                let idStr = (Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String).lowercased()
                if idStr.contains("russian") {
                    russianSource = src
                } else if idStr.contains("abc") || idStr.contains("us") || idStr.contains("en") {
                    englishSource = src
                }
            }
        }
    }
    
    func currentLanguage() -> Language {
        guard let cur = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return .other }
        guard let idPtr = TISGetInputSourceProperty(cur, kTISPropertyInputSourceID) else { return .other }
        let idStr = (Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String).lowercased()
        if idStr.contains("russian") { return .russian }
        if idStr.contains("abc") || idStr.contains("us") || idStr.contains("en") { return .english }
        return .other
    }
    
    @discardableResult
    func switchTo(_ lang: Language, waitForPropagate: Bool = true) -> Bool {
        refreshSources()
        let target = (lang == .russian ? russianSource : englishSource)
        guard let target = target else { return false }
        let res = TISSelectInputSource(target)
        lastTargetLanguage = lang
        lastSwitchTime = CFAbsoluteTimeGetCurrent()
        
        if waitForPropagate {
            // Wait up to 50ms for layout to propagate in window server
            for _ in 0..<5 {
                usleep(10_000)
                if currentLanguage() == lang { break }
            }
        }
        return res == noErr
    }
    
    @discardableResult
    func toggle() -> Language {
        let cur = currentLanguage()
        let next = cur.opposite
        switchTo(next, waitForPropagate: true)
        return next
    }
    
    @discardableResult
    func toggleFast() -> Language {
        let now = CFAbsoluteTimeGetCurrent()
        let cur = currentLanguage()
        let next: Language
        // If we switched recently (within 0.6s), alternate from lastTargetLanguage
        // to prevent getting stuck if macOS hasn't updated its input source cache yet!
        if let lastTarget = lastTargetLanguage, now - lastSwitchTime < 0.60 {
            next = lastTarget.opposite
        } else {
            next = (cur == .other) ? (lastTargetLanguage?.opposite ?? .english) : cur.opposite
        }
        
        switchTo(next, waitForPropagate: false)
        return next
    }
}
