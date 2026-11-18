import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()
    
    @Published var isEnabled: Bool = false
    
    private init() {
        refresh()
    }
    
    func refresh() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }
    
    func toggle() {
        set(!isEnabled)
    }
    
    func set(_ enable: Bool) {
        do {
            if enable {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            print("LaunchAtLogin change error: \(error)")
        }
        refresh()
    }
}

