import Foundation

/// 詞彙庫本地存儲
@Observable
final class VocabularyStore {
    static let shared = VocabularyStore()

    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard
    private let bundledVocabularyVersionKey = "com.typegood.bundledVocabularyVersion"
    private static let bundledVocabularyVersion = 2

    var library: VocabularyLibrary

    private var storageURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("TypeGood", isDirectory: true)
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("vocabulary.json")
    }

    private init() {
        if let data = try? Data(contentsOf: VocabularyStore.defaultStorageURL()),
           let decoded = try? JSONDecoder().decode(VocabularyLibrary.self, from: data) {
            self.library = decoded
            migrateBundledVocabularyIfNeeded()
        } else {
            self.library = VocabularyLibrary()
            loadDefaultVocabulary()
        }
    }

    private static func defaultStorageURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("TypeGood", isDirectory: true)
        return appDir.appendingPathComponent("vocabulary.json")
    }

    /// 載入內建預設詞彙
    private func loadDefaultVocabulary() {
        if let decoded = loadBundledVocabularyEntries() {
            library.entries = decoded
            library.lastModified = Date()
            save()
            defaults.set(Self.bundledVocabularyVersion, forKey: bundledVocabularyVersionKey)
        }
    }

    /// 將舊版內建詞彙遷移為新版預設，避免舊的大小寫修正規則長期殘留。
    private func migrateBundledVocabularyIfNeeded() {
        let storedVersion = defaults.integer(forKey: bundledVocabularyVersionKey)
        guard storedVersion < Self.bundledVocabularyVersion,
              let bundledEntries = loadBundledVocabularyEntries() else { return }

        if storedVersion < 2 {
            let oldDefaultIDs = Set((1...12).compactMap {
                UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))
            })
            library.entries.removeAll { oldDefaultIDs.contains($0.id) }
        }

        let existingIDs = Set(library.entries.map(\.id))
        let existingPairs = Set(library.entries.map { "\($0.source)\u{1F}\($0.target)" })
        let newEntries = bundledEntries.filter { entry in
            !existingIDs.contains(entry.id) &&
            !existingPairs.contains("\(entry.source)\u{1F}\(entry.target)")
        }

        if !newEntries.isEmpty {
            library.entries.append(contentsOf: newEntries)
            library.lastModified = Date()
            save()
        }

        defaults.set(Self.bundledVocabularyVersion, forKey: bundledVocabularyVersionKey)
    }

    private func loadBundledVocabularyEntries() -> [VocabularyEntry]? {
        guard let url = Bundle.main.url(forResource: "default_vocabulary", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([VocabularyEntry].self, from: data)
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(library) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    func resetToDefaultVocabulary() {
        library = VocabularyLibrary()
        loadDefaultVocabulary()
    }

    func add(source: String, target: String, note: String = "") {
        let entry = VocabularyEntry(source: source, target: target, note: note)
        library.add(entry)
        save()
    }

    func remove(at offsets: IndexSet) {
        library.remove(at: offsets)
        save()
    }

    func update(_ entry: VocabularyEntry) {
        library.update(entry)
        save()
    }

    /// 匯出詞彙庫為 JSON Data
    func exportJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(library.entries)
    }

    /// 從 JSON Data 匯入詞彙
    func importJSON(_ data: Data, replace: Bool = false) throws {
        let entries = try JSONDecoder().decode([VocabularyEntry].self, from: data)
        if replace {
            library.entries = entries
        } else {
            library.entries.append(contentsOf: entries)
        }
        library.lastModified = Date()
        save()
    }
}
