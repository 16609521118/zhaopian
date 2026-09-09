import Foundation
import UIKit

/// 已挂载的本地文件夹
struct MountedFolder: Identifiable, Hashable {
    let id: String          // 用路径作为稳定标识
    let url: URL
    let displayName: String
}

/// 文件夹挂载数据层：
/// 通过 UIDocumentPicker 选择用户本地文件夹，以安全作用域（security-scoped resource）
/// 直接映射访问真实目录（不复制文件），并用 bookmark 持久化，App 重启后仍可访问。
final class FolderViewModel: ObservableObject {
    @Published var folders: [MountedFolder] = []
    @Published var isMounting = false

    private let bookmarksKey = "mountedFolderBookmarks"

    init() {
        refreshFolders()
    }

    // MARK: - 挂载

    func mount(url: URL) {
        let opened = url.startAccessingSecurityScopedResource()
        defer {
            if opened {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope, .minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var bookmarks = loadBookmarks()
            bookmarks[url.path] = data
            saveBookmarks(bookmarks)
        } catch {
            return
        }
        refreshFolders()
    }

    func unmount(_ folder: MountedFolder) {
        var bookmarks = loadBookmarks()
        bookmarks.removeValue(forKey: folder.url.path)
        saveBookmarks(bookmarks)
        folder.url.stopAccessingSecurityScopedResource()
        refreshFolders()
    }

    // MARK: - 恢复（App 启动时）

    private func refreshFolders() {
        let bookmarks = loadBookmarks()
        var list: [MountedFolder] = []
        for (path, data) in bookmarks {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else {
                continue
            }
            _ = url.startAccessingSecurityScopedResource()
            let name = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName)
                ?? url.lastPathComponent
            list.append(MountedFolder(id: path, url: url, displayName: name))
        }
        list.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        folders = list
    }

    // MARK: - 持久化

    private func loadBookmarks() -> [String: Data] {
        guard let data = UserDefaults.standard.data(forKey: bookmarksKey),
              let dict = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? [String: Data]
        else {
            return [:]
        }
        return dict
    }

    private func saveBookmarks(_ dict: [String: Data]) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: dict, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: bookmarksKey)
        }
    }
}
