import Foundation
import UIKit
import UniformTypeIdentifiers

struct SavedFolder: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let bookmarkData: Data
}

final class BookmarkManager: NSObject, UIDocumentPickerDelegate {
    static let shared = BookmarkManager()
    private override init() {}

    @Published var savedFolders: [SavedFolder] = []
    @Published var activeFolderURL: URL?
    private let storeKey = "savedFolders.v1"

    func loadFolders() {
        guard let data = UserDefaults.standard.data(forKey: storeKey) else { return }
        if let decoded = try? JSONDecoder().decode([SavedFolder].self, from: data) {
            savedFolders = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(savedFolders) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    func pickFolder(from vc: UIViewController) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        picker.directoryURL = nil
        vc.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let item = SavedFolder(id: UUID(), name: url.lastPathComponent, bookmarkData: bookmark)
            savedFolders.append(item)
            persist()
        } catch {
            print("书签保存失败: \(error.localizedDescription)")
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}

    @discardableResult
    func resolveFolder(_ item: SavedFolder) -> URL? {
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: item.bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            if stale {
                print("书签已过期，需要重新挂载: \(item.name)")
                return nil
            }
            guard url.startAccessingSecurityScopedResource() else { return nil }
            return url
        } catch {
            print("解析书签失败: \(error.localizedDescription)")
            return nil
        }
    }

    func listVideoFiles(in folderURL: URL) -> [URL] {
        var videos: [URL] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let allowed: Set<String> = [
            "mp4", "m4v", "mov", "mkv", "avi", "flv", "wmv",
            "ts", "m2ts", "rmvb", "rm", "webm", "mpg", "mpeg",
            "3gp", "vob", "asf", "f4v"
        ]

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard allowed.contains(ext) else { continue }
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fileURL.path, isDirectory: &isDir)
            if isDir.boolValue { continue }
            videos.append(fileURL)
        }
        return videos.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
    }

    func remove(_ item: SavedFolder) {
        savedFolders.removeAll { $0.id == item.id }
        persist()
    }
}
