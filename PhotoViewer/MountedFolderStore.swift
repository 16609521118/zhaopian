//
//  MountedFolderStore.swift
//  PhotoViewer
//
//  挂载文件夹的持久化存储：安全作用域书签（Security-Scoped Bookmark）。
//  用户通过系统文件选择器授权文件夹后，App 把授权生成书签并持久化保存，
//  之后每次启动 / 访问时用书签还原 URL 并重新申请访问权，实现"真正挂载、不复制"。
//
//  注意（Apple 开发者论坛确认）：必须先 startAccessingSecurityScopedResource()
//  再生成书签，否则可能失败；解析书签后也要先 startAccessing 再访问文件。
//

import Foundation

struct MountedFolderRecord: Codable {
    let folderId: String
    let name: String
    let bookmarkBase64: String
    let createdAt: TimeInterval
}

final class MountedFolderStore {

    static let shared = MountedFolderStore()

    private let defaultsKey = "mountedFolders.v3"
    private let lock = NSLock()
    private var records: [String: MountedFolderRecord] = [:]

    private init() {
        load()
    }

    // MARK: - 写入书签

    /// 保存文件夹授权书签（不复制任何文件）。folderId 由调用方生成。
    /// 按 Apple 现行文档（iOS 26 SDK）：iOS 上用 .minimalBookmark 创建书签，
    /// 解析后仍是安全作用域 URL，仍需 startAccessing 后访问。
    func add(folderId: String, name: String, from url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try url.bookmarkData(options: .minimalBookmark,
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        let record = MountedFolderRecord(folderId: folderId,
                                         name: name,
                                         bookmarkBase64: data.base64EncodedString(),
                                         createdAt: Date().timeIntervalSince1970)
        lock.lock()
        records[folderId] = record
        save()
        lock.unlock()
    }

    // MARK: - 解析书签

    /// 还原书签对应的文件夹 URL（调用方仍需 startAccessing 后访问）。
    func resolve(folderId: String) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard let record = records[folderId],
              let data = Data(base64Encoded: record.bookmarkBase64) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 bookmarkDataIsStale: &isStale) else { return nil }
        return url
    }

    func name(of folderId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return records[folderId]?.name
    }

    func contains(_ folderId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return records[folderId] != nil
    }

    func remove(folderId: String) {
        lock.lock()
        records.removeValue(forKey: folderId)
        save()
        lock.unlock()
    }

    // MARK: - 持久化

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let list = try? JSONDecoder().decode([MountedFolderRecord].self, from: data) else { return }
        records = Dictionary(uniqueKeysWithValues: list.map { ($0.folderId, $0) })
    }

    private func save() {
        let list = Array(records.values)
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
