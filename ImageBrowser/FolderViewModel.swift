import Foundation

/// 已挂载的本地文件夹（Hashable 用于导航）
struct MountedFolder: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var bookmarkData: Data
    var url: URL
}

/// 挂载管理：系统文件夹选择器 → security-scoped bookmark 持久化（重启后仍可访问）
final class FolderViewModel: ObservableObject {
    @Published var folders: [MountedFolder] = []

    private let defaultsKey = "mountedFolders_v1"

    init() {
        load()
    }

    /// 挂载一个文件夹：创建 bookmark 并立即持有访问权限（保持到 App 结束）
    func mount(url: URL, name: String) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return "所选不是文件夹"
        }
        guard let bookmark = try? url.bookmarkData(
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return "无法创建访问凭证"
        }
        guard url.startAccessingSecurityScopedResource() else {
            return "无法获取文件夹访问权限"
        }
        if let existing = folders.firstIndex(where: { $0.url.path == url.path }) {
            folders[existing].name = name
            folders[existing].bookmarkData = bookmark
        } else {
            folders.append(MountedFolder(name: name, bookmarkData: bookmark, url: url))
        }
        save()
        return nil
    }

    func remove(_ folder: MountedFolder) {
        folder.url.stopAccessingSecurityScopedResource()
        folders.removeAll { $0.id == folder.id }
        save()
    }

    // MARK: - 持久化

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let list = try? JSONDecoder().decode([SavedFolder].self, from: data) else {
            return
        }
        folders = list.compactMap { saved -> MountedFolder? in
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: saved.bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { return nil }
            _ = url.startAccessingSecurityScopedResource()
            return MountedFolder(name: saved.name, bookmarkData: saved.bookmarkData, url: url)
        }
    }

    private func save() {
        let list = folders.map { SavedFolder(name: $0.name, bookmarkData: $0.bookmarkData) }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

private struct SavedFolder: Codable {
    let name: String
    let bookmarkData: Data
}
