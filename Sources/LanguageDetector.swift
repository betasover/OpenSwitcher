import Foundation
import AppKit

@MainActor
struct LanguageDetector {
    private static let enVowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
    private static let ruVowels: Set<Character> = ["а", "е", "ё", "и", "о", "у", "ы", "э", "ю", "я"]
    
    // Frequent Russian words in QWERTY
    private static let commonRuInEn: Set<String> = [
        "ghbdtn", "ntcn", "rfr", "ltkf", "xnj", "dct", "xtv", "yt", "jy", "jyb", "vs", "ds",
        "rjulf", "njkmrj", "cgfcb,j", "gjxtve", "pfxtv", "rulf", "nfr", "vtyz",
        "nt,z", "tuj", "tt", "bv", "bkb", "tckb", "xnj,s", "lf", "ytn",
        "plhfdcndeq", "pljhjdj", "[jhjij", "kexit", "ghjcnj", "ctqxfc", "gjnjv",
        "nj;t", "nfr;t", "gjckt", "vyt", "ytuj", "xtuj", "rjuj",
        "ghbdtnbr", "rhenj", "rfgtw", "kflyj", "gjrf", "pfnhf", "ctujlyz",
        "rfrbt", "rfrjq", "rfrfz", "rfrjt", "xnjkb", "ghj", "gjl", "yfl", "gthtl",
        "bp", "e;t", "ye", "dtlm", "tcnm", "kb", "vyt", "nt,t", "tve", "tq", "yf",
        "yfc", "dfc", "b[", "cvjnhb", "ltkfq", "pyf.", "pyftn", "vj;tn", "vj;yj",
        "yflj", "ye;yj", "ytkmpz", "gjikb", "gjtv", "xtkjdtr", "k.lb", "hfp", "ldf",
        "ghjdthrf", "hf,jnf", "gthtrk.xtybt", "zpsr", "gfhjkm", "kjuby", "cfqn", "gjxnf"
    ]
    
    // Frequent English words in ЙЦУКЕН
    private static let commonEnInRu: Set<String> = [
        "руддщ", "еру", "ершы", "ерфе", "ерштл", "ерун", "еруку", "еруыу",
        "црфе", "цруку", "црут", "цршср", "црщ", "црн",
        "цщкдв", "цщкв", "цщгдв", "цшер", "цшдд", "цшт",
        "ащк", "ащгтв", "ащкы", "нщг", "нщгк",
        "рудз", "сщву", "сщь", "сщтыщду", "куыгде", "куегкт", "куфв",
        "ыудуксе", "ыефке", "ыщгкс", "ыщьу", "ыуе", "ыекштп", "ыефегы",
        "ьфлу", "ьщку", "ьфт", "ьфз", "ьщвгду", "ьувшф", "ьуыыфпу",
        "йгукн", "сфт", "сщгдв", "фищге", "дшлу", "ешьу", "ящщь", "пуе", "зщые",
        "здуфыу", "цфке", "иге", "тще", "нуы", "тщ", "фтв", "щк", "ыщ", "ша"
    ]
    
    private static let ruPrefixesInEn = [
        "ghb", "ghj", "gjl", "yfl", "gtht", "xnj", "rfr", "rjulf", "plh",
        "pfxt", "gjxt", "njkm", "kex", "cgfc", "dce", "bkb", "tckb", "cvjn",
        "kfly", "rhen", "ctuj", "hf,j"
    ]
    
    // Impossible prefixes in legitimate Russian words (indicates QWERTY typed on RU)
    private static let impossibleRuPrefixes = [
        "цр", "цщ", "цш", "ащ", "нщ", "йг", "щк", "щг"
    ]
    
    private static func isSpelledCorrectly(_ word: String, language: String) -> Bool {
        let lower = word.lowercased()
        if language == "en" && UserDictionary.shared.isKnownEnglish(lower) {
            return true
        }
        if language == "ru" && UserDictionary.shared.isKnownRussian(lower) {
            return true
        }
        
        let range = NSSpellChecker.shared.checkSpelling(
            of: word,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        return range.location == NSNotFound
    }
    
    static func shouldSwitchFromEnToRu(_ word: String) -> Bool {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2 else { return false }
        let lower = clean.lowercased()
        
        // 1. Exact high-frequency dictionary match
        if commonRuInEn.contains(lower) { return true }
        
        // 2. Punctuation inside Russian letters on QWERTY (e.g. [, ], ;, ,, .)
        let ruPunct: [Character] = ["[", "]", ";", ",", "'"]
        if ruPunct.contains(where: { lower.contains($0) }) {
            let letters = lower.filter { $0.isLetter }
            if letters.count >= 2 { return true }
        }
        
        // 3. If it is already a valid English word in macOS dictionary, do not switch
        if isSpelledCorrectly(lower, language: "en") {
            return false
        }
        
        // 4. Converted word is a valid Russian word in macOS dictionary
        let ruWord = KeyboardMapper.shared.convertToRussian(lower)
        if isSpelledCorrectly(ruWord, language: "ru") {
            return true
        }
        
        // 5. Russian prefixes typed in English
        for p in ruPrefixesInEn {
            if lower.hasPrefix(p) { return true }
        }
        
        // 6. Vowel heuristic: English word of 3+ letters has 0 English vowels, but converted has Russian vowels
        let enVowelCount = lower.filter { enVowels.contains($0) }.count
        let ruVowelCount = ruWord.filter { ruVowels.contains($0) }.count
        if lower.count >= 3 && enVowelCount == 0 && ruVowelCount >= 1 {
            return true
        }
        
        return false
    }
    
    static func shouldSwitchFromRuToEn(_ word: String) -> Bool {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2 else { return false }
        let lower = clean.lowercased()
        
        // 1. If it is already a valid Russian word, NEVER switch it!
        if isSpelledCorrectly(lower, language: "ru") {
            return false
        }
        
        // 2. Exact high-frequency dictionary match
        if commonEnInRu.contains(lower) { return true }
        
        // 3. Converted word is a valid English word in macOS dictionary
        let enWord = KeyboardMapper.shared.convertToEnglish(lower)
        if isSpelledCorrectly(enWord, language: "en") {
            return true
        }
        
        // 4. In Russian, NO word starts with 'ы', 'ь', 'ъ'
        if lower.hasPrefix("ы") || lower.hasPrefix("ь") || lower.hasPrefix("ъ") {
            let enVowelCount = enWord.filter { enVowels.contains($0) }.count
            if enVowelCount >= 1 || lower.count <= 2 {
                return true
            }
        }
        
        // 5. Impossible Russian letter combinations at start
        for p in impossibleRuPrefixes {
            if lower.hasPrefix(p) && lower.count >= 2 {
                return true
            }
        }
        
        // 6. Vowel heuristic: Russian word of 3+ letters has 0 Russian vowels, but converted has English vowels
        let ruVowelCount = lower.filter { ruVowels.contains($0) }.count
        let enVowelCount = enWord.filter { enVowels.contains($0) }.count
        if lower.count >= 3 && ruVowelCount == 0 && enVowelCount >= 1 {
            return true
        }
        
        return false
    }
    
    static func detectMismatch(word: String) -> LayoutManager.Language? {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2 else { return nil }
        
        // Never auto-switch words with digits (passwords, code, v2, win64, etc.)
        if clean.contains(where: { $0.isNumber }) { return nil }
        
        // Never auto-switch URLs, paths, or email fragments
        if clean.contains("@") || clean.contains("/") || clean.contains("\\") || clean.contains(":") || clean.contains("http") {
            return nil
        }
        
        // Check character script
        let hasLatin = clean.contains { $0.isASCII && $0.isLetter }
        let hasCyrillic = clean.contains { ("\u{0400}"..."\u{04FF}").contains($0) }
        
        if hasLatin && !hasCyrillic {
            if shouldSwitchFromEnToRu(clean) {
                return .russian
            }
        } else if hasCyrillic && !hasLatin {
            if shouldSwitchFromRuToEn(clean) {
                return .english
            }
        }
        
        return nil
    }
    
    static func detectDoubleCaps(word: String) -> String? {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 3 else { return nil }
        let chars = Array(clean)
        guard chars[0].isUppercase && chars[1].isUppercase else { return nil }
        guard chars[2].isLowercase else { return nil }
        for c in chars.dropFirst(2) {
            if c.isLetter && !c.isLowercase { return nil }
        }
        let fixed = String(chars[0]) + String(chars[1]).lowercased() + String(chars.dropFirst(2))
        return fixed
    }
}
