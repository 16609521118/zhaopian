import Foundation

// MARK: - 挂载的本地文件夹模型

struct MountedFolder: Codable, Equatable {
    let id: UUID
    var name: String
    var url: URL
    var bookmarkData: Data
    var createdAt: Date

    init(url: URL, bookmarkData: Data) {
        self.id = UUID()
        self.name = url.lastPathComponent.isEmpty ? "本地文件夹" : url.lastPathComponent
        self.url = url
        self.bookmarkData = bookmarkData
        self.createdAt = Date()
    }
}

// MARK: - 书签存取（持久化到 Documents/mounted_folders.json）

final class BookmarkStore {

    static let shared = BookmarkStore()

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("mounted_folders.json")
    }()

    private(set) var folders: [MountedFolder] = []

    private init() {
        load()
    }

    func add(_ folder: MountedFolder) {
        folders.append(folder)
        save()
    }

    func replace(_ folder: MountedFolder, at index: Int) {
        guard folders.indices.contains(index) else { return }
        folders[index] = folder
        save()
    }

    func remove(at index: Int) {
        guard folders.indices.contains(index) else { return }
        folders.remove(at: index)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([MountedFolder].self, from: data) else { return }
        folders = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - 安全作用域书签工具
// 与 SenPlayer「挂载本地文件夹」同机制：
// 1. 用 UIDocumentPicker 选中文件夹后，iOS 对该 URL 授予安全作用域访问权
// 2. 把 URL 存为书签（minimalBookmark）持久化，实现"挂载"效果
// 3. 之后每次访问前调用 startAccessingSecurityScopedResource() 重建访问权

enum SecurityScopedBookmark {

    /// 在持有访问权时调用，把 URL 转成可持久化的书签数据
    static func make(for url: URL) -> Data? {
        try? url.bookmarkData(options: .minimalBookmark,
                              includingResourceValuesForKeys: nil,
                              relativeTo: nil)
    }

    /// 解析书签；isStale 为 true 表示书签已过期，需要重新选择文件夹
    static func resolve(_ data: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &isStale) else { return nil }
        return (url, isStale)
    }
}
