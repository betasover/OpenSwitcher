import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("autoSwitch") private var autoSwitchEnabled: Bool = true
    @AppStorage("doubleShift") private var doubleShiftEnabled: Bool = true
    @AppStorage("doubleCaps") private var doubleCapsEnabled: Bool = true
    @AppStorage("soundEnabled") private var soundEnabled: Bool = false
    @ObservedObject private var launchAtLogin = LaunchAtLogin.shared
    @ObservedObject private var exceptions = AppExceptions.shared
    @ObservedObject private var userDict = UserDictionary.shared
    @ObservedObject private var soundManager = SoundManager.shared
    
    @State private var selectedException: String?
    @State private var isAccessibilityTrusted: Bool = AXIsProcessTrusted()
    @State private var newWordText: String = ""
    
    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("Основные", systemImage: "gearshape")
                }
            
            exceptionsTab
                .tabItem {
                    Label("Исключения", systemImage: "xmark.app")
                }
            
            dictionaryTab
                .tabItem {
                    Label("Словарь", systemImage: "text.book.closed")
                }
            
            aboutTab
                .tabItem {
                    Label("О программе", systemImage: "info.circle")
                }
        }
        .frame(width: 520, height: 430)
        .padding()
        .onAppear {
            isAccessibilityTrusted = AXIsProcessTrusted()
            launchAtLogin.refresh()
        }
    }
    
    // MARK: - General Tab
    private var generalTab: some View {
        Form {
            Section("Режимы работы") {
                Toggle("Автоматическое переключение", isOn: $autoSwitchEnabled)
                Text("Анализирует набранные буквы и автоматически переключает раскладку при ошибке.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Toggle("Исправление по двойному Shift", isOn: $doubleShiftEnabled)
                Text("Два быстрых нажатия Shift исправляют последнее набранное слово или выделенный фрагмент текста.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Toggle("Исправлять двойные заглавные (ПРивет → Привет)", isOn: $doubleCapsEnabled)
                Text("Устраняет случайный ввод двух заглавных букв подряд при задержке отпускания Shift.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Toggle("Звуковой сигнал при исправлении", isOn: $soundEnabled)
                Text("Воспроизводит мягкий щелчок при автоисправлении слова или по двойному Shift.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if soundEnabled {
                    HStack(spacing: 12) {
                        Picker("Мелодия", selection: $soundManager.currentSoundType) {
                            ForEach(SwitcherSound.allCases) { sound in
                                Text(sound.displayName).tag(sound)
                            }
                        }
                        .pickerStyle(.menu)
                        
                        Button(action: {
                            soundManager.preview(soundManager.currentSoundType)
                        }) {
                            Label("Слушать", systemImage: "play.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .help("Прослушать выбранный звук")
                    }
                    .padding(.vertical, 2)
                }
                
                Toggle("Запуск при входе в систему", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.set($0) }
                ))
            }
            
            Section("Системный доступ") {
                HStack {
                    Circle()
                        .fill(isAccessibilityTrusted ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    
                    Text(isAccessibilityTrusted ? "Универсальный доступ активен" : "Требуется разрешение Accessibility")
                        .font(.callout)
                    
                    Spacer()
                    
                    if !isAccessibilityTrusted {
                        Button("Открыть Настройки...") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
                
                if !isAccessibilityTrusted {
                    Text("💡 Если переключатель уже включен, удалите OpenSwitcher через кнопку «минус» [-] в настройках macOS и добавьте заново через [+].")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            isAccessibilityTrusted = AXIsProcessTrusted()
        }
    }
    
    // MARK: - Exceptions Tab
    private var exceptionsTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Приложения, в которых автопереключение отключено:")
                .font(.callout)
                .foregroundColor(.secondary)
            
            if exceptions.allExceptions.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "app.dashed")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("Нет исключений")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Нажмите «+ Добавить приложение...», чтобы отключить автопереключение в нужных программах.")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(6)
            } else {
                List(selection: $selectedException) {
                    ForEach(exceptions.allExceptions, id: \.self) { bundleId in
                        let meta = AppMetadataResolver.resolve(bundleID: bundleId)
                        HStack(spacing: 12) {
                            Image(nsImage: meta.icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .cornerRadius(5)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meta.name)
                                    .font(.system(size: 13, weight: .medium))
                                
                                Text(meta.id)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if !meta.isInstalled {
                                Text("Не установлено")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(4)
                            }
                            
                            // Cross [✕] button right inside the row
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    exceptions.remove(bundleID: bundleId)
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundColor(Color.secondary.opacity(0.8))
                            }
                            .buttonStyle(.borderless)
                            .help("Удалить \(meta.name) из исключений")
                        }
                        .padding(.vertical, 3)
                        .tag(bundleId)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .cornerRadius(6)
            }
            
            HStack {
                Button(action: addAppPanel) {
                    Label("Добавить приложение...", systemImage: "plus")
                }
                
                Button(action: removeSelected) {
                    Label("Удалить выбранное", systemImage: "minus")
                }
                .disabled(selectedException == nil)
                
                Spacer()
                
                Text("Всего: \(exceptions.allExceptions.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Dictionary Tab
    private var dictionaryTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Словарь терминов и пользовательских слов:")
                .font(.callout)
                .foregroundColor(.secondary)
            
            HStack {
                TextField("Добавить слово (например: github, figma, сленг)", text: $newWordText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addNewWord() }
                
                Button("Добавить", action: addNewWord)
                    .disabled(newWordText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            
            if userDict.userWords.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("Встроенный IT-словарь активен")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Термины (github, docker, figma, notion и др.) уже встроены.\nНовые слова запоминаются автоматически при нажатии Double Shift.")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(6)
            } else {
                List {
                    ForEach(userDict.userWords, id: \.self) { word in
                        HStack {
                            Text(word)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                            
                            Spacer()
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    userDict.unlearn(word)
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color.secondary.opacity(0.7))
                            }
                            .buttonStyle(.borderless)
                            .help("Удалить слово из словаря")
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .cornerRadius(6)
            }
            
            HStack {
                Text("💡 Нажатие Double Shift на незнакомом слове автоматически обучает приложение.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Добавлено слов: \(userDict.userWords.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - About Tab
    private var aboutTab: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "keyboard.badge.ellipsis")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundColor(.accentColor)
            
            Text("OpenSwitcher")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Версия 1.0.0")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Легковесный и быстрый автоматический переключатель раскладки для macOS, вдохновленный Caramba Switcher.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Divider()
                .padding(.vertical, 8)
            
            VStack(alignment: .leading, spacing: 6) {
                Label("Автоматическое переключение EN ↔ RU", systemImage: "checkmark.circle.fill")
                Label("Устранение двойных заглавных (ПРивет → Привет)", systemImage: "checkmark.circle.fill")
                Label("Исправление слова или выделенного текста по Double Shift", systemImage: "checkmark.circle.fill")
                Label("Словарь IT-терминов и самообучение по Double Shift", systemImage: "checkmark.circle.fill")
                Label("Черный список приложений-исключений", systemImage: "checkmark.circle.fill")
                Label("Соблюдение приватности: не сохраняет и не передает нажатия клавиш", systemImage: "lock.shield.fill")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            Spacer()
        }
    }
    
    private func addAppPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Выбрать"
        panel.message = "Выберите приложения для добавления в список исключений"
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                exceptions.addFromURL(url)
            }
        }
    }
    
    private func removeSelected() {
        guard let id = selectedException else { return }
        exceptions.remove(bundleID: id)
        selectedException = nil
    }
    
    private func addNewWord() {
        let clean = newWordText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        userDict.learn(clean)
        newWordText = ""
    }
}
