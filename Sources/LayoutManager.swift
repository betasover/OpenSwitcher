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
    
    init() {
        refreshSources()
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
        let cur = currentLanguage()
        let next = cur.opposite
        switchTo(next, waitForPropagate: false)
        return next
    }
}

