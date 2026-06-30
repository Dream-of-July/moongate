import Foundation

public struct LanguageCatalogEntry: Equatable, Sendable {
    public let code: String
    public let englishName: String
    public let chineseName: String
    public let nativeName: String
    public let aliases: [String]
    public let isCommon: Bool

    public var displayName: String { nativeName.isEmpty ? englishName : nativeName }
}

public enum LanguageCatalog {
    public static let commonLanguageCodes: [String] = ["en", "ja", "zh-Hans", "ko", "yue"]

    private static let aliasNormalization: [String: String] = [
        "en-us": "en", "en-gb": "en", "eng": "en",
        "ja-jp": "ja", "jpn": "ja", "jp": "ja",
        "ko-kr": "ko", "kor": "ko", "kr": "ko",
        "zh": "zh-Hans", "zh-cn": "zh-Hans", "zh-sg": "zh-Hans", "zh-hans": "zh-Hans", "cmn": "zh-Hans",
        "zh-tw": "zh-Hant", "zh-hk": "zh-Hant", "zh-mo": "zh-Hant", "zh-hant": "zh-Hant",
        "yue-hk": "yue",
        "iw": "he",
        "in": "id",
        "tl": "fil"
    ]

    private static let entries: [LanguageCatalogEntry] = [
        entry("en", "English", "英语", "English", ["english", "eng", "en-us", "en-gb"], true),
        entry("ja", "Japanese", "日语", "日本語", ["japanese", "jpn", "jp", "日文"], true),
        entry("zh-Hans", "Simplified Chinese", "简体中文", "中文", ["zh", "zh-cn", "cmn", "mandarin", "chinese", "中文", "汉语", "普通话"], true),
        entry("zh-Hant", "Traditional Chinese", "繁体中文", "繁體中文", ["zh-tw", "zh-hk", "traditional chinese"], false),
        entry("ko", "Korean", "韩语", "한국어", ["korean", "kor", "ko-kr", "韓国語"], true),
        entry("yue", "Cantonese", "粤语", "粵語", ["cantonese", "粤语", "廣東話", "广东话"], true),
        entry("es", "Spanish", "西班牙语", "Español", ["spanish", "es-es", "es-mx"], false),
        entry("fr", "French", "法语", "Français", ["french", "fra", "fre", "fr-fr"], false),
        entry("de", "German", "德语", "Deutsch", ["german", "deu", "ger", "de-de"], false),
        entry("it", "Italian", "意大利语", "Italiano", ["italian", "ita", "it-it"], false),
        entry("pt", "Portuguese", "葡萄牙语", "Português", ["portuguese", "por", "pt-br", "pt-pt"], false),
        entry("vi", "Vietnamese", "越南语", "Tiếng Việt", ["vietnamese", "vie", "vi-vn"], false),
        entry("id", "Indonesian", "印尼语", "Bahasa Indonesia", ["indonesian", "ind", "in"], false),
        entry("fil", "Filipino", "菲律宾语", "Filipino", ["filipino", "tagalog", "tl"], false),
        entry("he", "Hebrew", "希伯来语", "עברית", ["hebrew", "heb", "iw"], false),
        entry("si", "Sinhala", "僧伽罗语", "සිංහල", ["sinhala", "sin", "සිංහල"], false)
    ]

    private static let entriesByCode: [String: LanguageCatalogEntry] = {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.code, $0) })
    }()

    public static func normalize(_ code: String?) -> String {
        guard let code else { return "" }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let folded = trimmed.lowercased()
        if let mapped = aliasNormalization[folded] { return mapped }
        if folded.hasPrefix("zh-") {
            return folded.contains("hant") || folded.contains("-tw") || folded.contains("-hk") ? "zh-Hant" : "zh-Hans"
        }
        if let dash = folded.firstIndex(of: "-") {
            let base = String(folded[..<dash])
            return aliasNormalization[base] ?? base
        }
        return aliasNormalization[folded] ?? folded
    }

    public static func displayName(for code: String) -> String {
        let normalized = normalize(code)
        if let entry = entriesByCode[normalized] {
            return entry.isCommon ? entry.displayName : entry.englishName
        }
        return TranslationLanguage.sourceDisplayName(for: normalized)
            ?? normalized
    }

    public static func isCommon(_ code: String) -> Bool {
        commonLanguageCodes.contains(normalize(code))
    }

    public static func isRareLanguage(_ code: String) -> Bool {
        let normalized = normalize(code)
        guard !normalized.isEmpty else { return false }
        if let entry = entriesByCode[normalized] {
            return !entry.isCommon
        }
        return true
    }

    public static func commonEntries() -> [LanguageCatalogEntry] {
        commonLanguageCodes.compactMap { entriesByCode[$0] }
    }

    public static func search(_ query: String) -> [LanguageCatalogEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return commonEntries() }
        let normalizedQuery = normalize(trimmed)
        let folded = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
        let matches = entries.filter { entry in
            if entry.code == normalizedQuery { return true }
            let fields = [entry.code, entry.englishName, entry.chineseName, entry.nativeName] + entry.aliases
            return fields.contains { field in
                field.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .lowercased()
                    .contains(folded)
            }
        }
        return matches.sorted { lhs, rhs in
            if lhs.isCommon != rhs.isCommon { return lhs.isCommon }
            return lhs.englishName < rhs.englishName
        }
    }

    private static func entry(
        _ code: String,
        _ englishName: String,
        _ chineseName: String,
        _ nativeName: String,
        _ aliases: [String],
        _ isCommon: Bool
    ) -> LanguageCatalogEntry {
        LanguageCatalogEntry(
            code: code,
            englishName: englishName,
            chineseName: chineseName,
            nativeName: nativeName,
            aliases: aliases,
            isCommon: isCommon
        )
    }
}
