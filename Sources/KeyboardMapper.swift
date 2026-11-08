import Foundation

struct KeyboardMapper {
    static let shared = KeyboardMapper()
    
    // Standard QWERTY and Russian PC keyboard layout pairs
    private let enChars = "qwertyuiop[]asdfghjkl;'zxcvbnm,./`QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?~@#$^&"
    private let ruChars = "йцукенгшщзхъфывапролджэячсмитьбю.ёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,Ё\"№;:?"
    
    private var enToRu = [Character: Character]()
    private var ruToEn = [Character: Character]()
    
    init() {
        for (e, r) in zip(enChars, ruChars) {
            enToRu[e] = r
            ruToEn[r] = e
        }
    }
    
    func convertToRussian(_ text: String) -> String {
        String(text.map { enToRu[$0] ?? $0 })
    }
    
    func convertToEnglish(_ text: String) -> String {
        String(text.map { ruToEn[$0] ?? $0 })
    }
    
    func convert(_ text: String, to language: LayoutManager.Language) -> String {
        switch language {
        case .russian:
            return convertToRussian(text)
        case .english:
            return convertToEnglish(text)
        case .other:
            return text
        }
    }
}

