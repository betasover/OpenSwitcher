import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    
    override init() {
        super.init()
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.title = "⌥ OS"
            button.toolTip = "OpenSwitcher — умный переключатель раскладки"
        }
        
        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        buildMenu()
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        buildMenu()
    }
    
    private func buildMenu() {
        menu.removeAllItems()
        
        // Header
        let headerItem = NSMenuItem(title: "OpenSwitcher v1.0", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        
        let curLang = LayoutManager.shared.currentLanguage().rawValue
        let langItem = NSMenuItem(title: "Текущая раскладка: \(curLang)", action: #selector(toggleLayoutClicked), keyEquivalent: "")
        langItem.target = self
        menu.addItem(langItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Auto-switch toggle
        let autoItem = NSMenuItem(title: "Автопереключение", action: #selector(toggleAutoSwitch), keyEquivalent: "")
        autoItem.target = self
        autoItem.state = EventTapManager.shared.autoSwitchEnabled ? .on : .off
        menu.addItem(autoItem)
        
        // Double shift toggle
        let dsItem = NSMenuItem(title: "Двойной Shift (исправление слова)", action: #selector(toggleDoubleShift), keyEquivalent: "")
        dsItem.target = self
        dsItem.state = EventTapManager.shared.doubleShiftEnabled ? .on : .off
        menu.addItem(dsItem)
        
        // Fast Fn / Globe toggle
        let fnItem = NSMenuItem(title: "Мгновенный Fn / 🌐 (без задержки)", action: #selector(toggleFastFn), keyEquivalent: "")
        fnItem.target = self
        fnItem.state = FnSwitchManager.shared.isEnabled ? .on : .off
        menu.addItem(fnItem)
        
        // Sound toggle
        let soundEnabled = UserDefaults.standard.bool(forKey: "soundEnabled")
        let soundItem = NSMenuItem(title: "Звуковой сигнал", action: #selector(toggleSound), keyEquivalent: "")
        soundItem.target = self
        soundItem.state = soundEnabled ? .on : .off
        menu.addItem(soundItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Frontmost app toggle
        if let front = NSWorkspace.shared.frontmostApplication,
           let name = front.localizedName,
           let bundleId = front.bundleIdentifier {
            let isIgnored = AppExceptions.shared.isIgnored(bundleID: bundleId)
            let appTitle = isIgnored ? "✕  Удалить \(name) из исключений" : "Добавить \(name) в исключения"
            let appItem = NSMenuItem(title: appTitle, action: #selector(toggleFrontmostAppException), keyEquivalent: "")
            appItem.target = self
            menu.addItem(appItem)
        }
        
        // Exceptions list directly in the dropdown menu
        let exceptionsList = AppExceptions.shared.allExceptions
        if !exceptionsList.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let header = NSMenuItem(title: "Исключения (нажмите ✕ для удаления):", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            
            for bundle in exceptionsList {
                let meta = AppMetadataResolver.resolve(bundleID: bundle)
                let item = makeExceptionMenuItem(meta: meta, bundleId: bundle)
                menu.addItem(item)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Accessibility check
        let isTrusted = AXIsProcessTrusted()
        let accTitle = isTrusted ? "✓ Доступ к вводу разрешен" : "⚠️ Требуется доступ (Accessibility)..."
        let accItem = NSMenuItem(title: accTitle, action: #selector(checkAccessibility), keyEquivalent: "")
        accItem.target = self
        menu.addItem(accItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(title: "Настройки...", action: #selector(openSettingsClicked), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Завершить OpenSwitcher", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    private func makeExceptionMenuItem(meta: AppMetadata, bundleId: String) -> NSMenuItem {
        let item = NSMenuItem(title: "✕  \(meta.name)", action: #selector(removeExceptionClicked(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = bundleId
        item.toolTip = "Удалить \(meta.name) из исключений"
        
        let attr = NSMutableAttributedString()
        attr.append(NSAttributedString(string: "✕  ", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.systemRed
        ]))
        attr.append(NSAttributedString(string: meta.name, attributes: [
            .font: NSFont.menuFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]))
        item.attributedTitle = attr
        
        if let iconCopy = meta.icon.copy() as? NSImage {
            iconCopy.size = NSSize(width: 16, height: 16)
            item.image = iconCopy
        }
        return item
    }
    
    @objc private func toggleLayoutClicked() {
        LayoutManager.shared.toggle()
        buildMenu()
    }
    
    @objc private func toggleAutoSwitch() {
        EventTapManager.shared.autoSwitchEnabled.toggle()
        buildMenu()
    }
    
    @objc private func toggleDoubleShift() {
        EventTapManager.shared.doubleShiftEnabled.toggle()
        buildMenu()
    }
    
    @objc private func toggleFastFn() {
        FnSwitchManager.shared.isEnabled.toggle()
        buildMenu()
    }
    
    @objc private func toggleSound() {
        let cur = UserDefaults.standard.bool(forKey: "soundEnabled")
        UserDefaults.standard.set(!cur, forKey: "soundEnabled")
        buildMenu()
    }
    
    @objc private func toggleFrontmostAppException() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleId = front.bundleIdentifier else { return }
        AppExceptions.shared.toggle(bundleID: bundleId)
        buildMenu()
    }
    
    @objc private func removeExceptionClicked(_ sender: NSMenuItem) {
        if let bundle = sender.representedObject as? String {
            AppExceptions.shared.remove(bundleID: bundle)
            buildMenu()
        }
    }
    
    @objc private func checkAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    @objc private func openSettingsClicked() {
        SettingsWindowController.shared.show()
    }
    
    @objc private func quitClicked() {
        FnSwitchManager.shared.restoreSystemDefaultsOnQuit()
        NSApplication.shared.terminate(nil)
    }
}
