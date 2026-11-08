import AppKit

struct AppMetadata: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
    let isInstalled: Bool
}

enum AppMetadataResolver {
    static func resolve(bundleID: String) -> AppMetadata {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return AppMetadata(id: bundleID, name: name, icon: icon, isInstalled: true)
        }
        
        let parts = bundleID.split(separator: ".")
        let fallbackName = parts.last.map { String($0).capitalized } ?? bundleID
        let genericIcon = NSWorkspace.shared.icon(for: .application)
        return AppMetadata(id: bundleID, name: fallbackName, icon: genericIcon, isInstalled: false)
    }
}

