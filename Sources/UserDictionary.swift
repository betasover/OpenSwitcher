import Foundation
import Combine

@MainActor
final class UserDictionary: ObservableObject {
    static let shared = UserDictionary()
    
    private let defaultsKey = "OpenSwitcher_UserWords_v1"
    
    @Published var userWords: [String] = []
    
    // Tech & modern brands missing from standard macOS spellchecker
    private let builtInTechWords: Set<String> = [
        "github", "gitlab", "docker", "figma", "notion", "telegram", "slack",
        "google", "youtube", "chatgpt", "openai", "gemini", "anthropic", "claude",
        "yandex", "yandex.ru", "яндекс", "mail", "mail.ru", "маил", "майл", "мейл",
        "vk", "вк", "ozon", "озон", "wildberries", "вайлдберриз", "sber", "сбер",
        "tinkoff", "тинькофф", "avito", "авито", "kinopoisk", "кинопоиск", "rutube", "рутуб",
        "python", "swiftui", "macos", "ios", "android", "linux", "ubuntu",
        "frontend", "backend", "devops", "kubernetes", "k8s", "vscode", "xcode",
        "jira", "confluence", "trello", "asana", "miro", "linear",
        "redis", "postgres", "postgresql", "mysql", "mongodb", "sqlite",
        "nginx", "apache", "graphql", "oauth", "webhook", "api", "rest", "grpc",
        "config", "debug", "async", "await", "repo", "rebase", "commit",
        "npm", "yarn", "pnpm", "npx", "bun", "node", "nodejs", "webpack", "vite",
        "react", "vue", "angular", "svelte", "tailwind", "typescript", "javascript",
        "json", "yaml", "toml", "xml", "html", "css", "scss",
        "wifi", "bluetooth", "airdrop", "safari", "chrome", "firefox", "brave",
        "spotify", "netflix", "tiktok", "instagram", "twitter", "reddit"
    ]
    
    private var allEnglishWordsSet: Set<String> = []
    private var allRussianWordsSet: Set<String> = []
    
    private init() {
        let saved = UserDefaults.standard.array(forKey: defaultsKey) as? [String] ?? []
        userWords = saved.sorted()
        rebuildSets()
    }
    
    private func rebuildSets() {
        allEnglishWordsSet = []
        allRussianWordsSet = []
        
        let allWords = builtInTechWords.union(userWords)
        for w in allWords {
            let lower = w.lowercased()
            if lower.contains(where: { ("\u{0400}"..."\u{04FF}").contains($0) }) {
                allRussianWordsSet.insert(lower)
            } else {
                allEnglishWordsSet.insert(lower)
            }
        }
    }
    
    func isKnownEnglish(_ word: String) -> Bool {
        allEnglishWordsSet.contains(word.lowercased())
    }
    
    func isKnownRussian(_ word: String) -> Bool {
        allRussianWordsSet.contains(word.lowercased())
    }
    
    func learn(_ word: String) {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard clean.count >= 2, !builtInTechWords.contains(clean), !userWords.contains(clean) else { return }
        
        userWords.append(clean)
        userWords.sort()
        UserDefaults.standard.set(userWords, forKey: defaultsKey)
        rebuildSets()
    }
    
    func unlearn(_ word: String) {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        userWords.removeAll { $0 == clean }
        UserDefaults.standard.set(userWords, forKey: defaultsKey)
        rebuildSets()
    }
}

