import AppKit
import Combine

enum SwitcherSound: String, CaseIterable, Identifiable {
    case pop = "pop"
    case key = "key"
    case bottle = "bottle"
    case purr = "purr"
    case tink = "tink"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .pop: return "Мягкий щелчок (Pop)"
        case .key: return "Системный клик (Key Click)"
        case .bottle: return "Деревянный стук (Bottle)"
        case .purr: return "Мягкий тон (Purr)"
        case .tink: return "Колокольчик (Tink)"
        }
    }
    
    func createSound() -> NSSound? {
        let sound: NSSound?
        switch self {
        case .pop:
            sound = NSSound(named: "Pop")
        case .key:
            sound = NSSound(contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Media Keys.aif", byReference: true)
        case .bottle:
            sound = NSSound(named: "Bottle")
        case .purr:
            sound = NSSound(named: "Purr")
        case .tink:
            sound = NSSound(named: "Tink")
        }
        sound?.volume = 0.45
        return sound
    }
}

@MainActor
final class SoundManager: ObservableObject {
    static let shared = SoundManager()
    
    private let soundKey = "selectedSound"
    private var cachedSound: NSSound?
    
    @Published var currentSoundType: SwitcherSound {
        didSet {
            UserDefaults.standard.set(currentSoundType.rawValue, forKey: soundKey)
            cachedSound = currentSoundType.createSound()
        }
    }
    
    private init() {
        let raw = UserDefaults.standard.string(forKey: soundKey) ?? SwitcherSound.pop.rawValue
        let type = SwitcherSound(rawValue: raw) ?? .pop
        self.currentSoundType = type
        self.cachedSound = type.createSound()
    }
    
    func play() {
        guard UserDefaults.standard.bool(forKey: "soundEnabled") else { return }
        if cachedSound == nil {
            cachedSound = currentSoundType.createSound()
        }
        cachedSound?.stop()
        cachedSound?.play()
    }
    
    func preview(_ soundType: SwitcherSound) {
        let snd = soundType.createSound()
        snd?.play()
    }
}
