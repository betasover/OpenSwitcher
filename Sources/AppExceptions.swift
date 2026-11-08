import Foundation
import AppKit
import Combine

@MainActor
final class AppExceptions: ObservableObject {
    static let shared = AppExceptions()
    
    private let defaultsKey = "OpenSwitcher_IgnoredApps"
    
    @Published var allExceptions: [String] = []
    
    init() {
        // Clear legacy default pre-configured exceptions once
        if !UserDefaults.standard.bool(forKey: "OpenSwitcher_CleanExceptions_v2") {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            UserDefaults.standard.set(true, forKey: "OpenSwitcher_CleanExceptions_v2")
        }
        
        allExceptions = (UserDefaults.standard.array(forKey: defaultsKey) as? [String])?.sorted() ?? []
    }
    
    func isIgnored(bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return allExceptions.contains(id)
    }
    
    func isFrontmostAppIgnored() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        return isIgnored(bundleID: front.bundleIdentifier)
    }
    
    func toggle(bundleID: String) {
        if let idx = allExceptions.firstIndex(of: bundleID) {
            allExceptions.remove(at: idx)
        } else {
            allExceptions.append(bundleID)
            allExceptions.sort()
        }
        UserDefaults.standard.set(allExceptions, forKey: defaultsKey)
    }
    
    func add(bundleID: String) {
        guard !allExceptions.contains(bundleID) else { return }
        allExceptions.append(bundleID)
        allExceptions.sort()
        UserDefaults.standard.set(allExceptions, forKey: defaultsKey)
    }
    
    func remove(bundleID: String) {
        allExceptions.removeAll { $0 == bundleID }
        UserDefaults.standard.set(allExceptions, forKey: defaultsKey)
    }
    
    func addFromURL(_ url: URL) {
        if let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
            add(bundleID: id)
        }
    }
}
