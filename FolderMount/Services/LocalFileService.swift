import Foundation

/// 本地沙盒文件管理：下载根目录、目录枚举、删除、共享。
enum LocalFileService {
    static let fm = FileManager.default

    static var documentsURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// 应用内"本地"根目录（相当于本机挂载区）
    static var localRootURL: URL {
        let dir = documentsURL.appendingPathComponent("Local", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 某个挂载点的下载目录
    static func downloadDirectory(for mountName: String) -> URL {
        let dir = documentsURL.appendingPathComponent("Downloads/\(Formatters.safeFileName(mountName))", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 枚举本地目录（顶层的挂载下载目录与 Local 根）
    static func localDirectories() -> [URL] {
        let downloadsRoot = documentsURL.appendingPathComponent("Downloads", isDirectory: true)
        try? fm.createDirectory(at: downloadsRoot, withIntermediateDirectories: true)
        let candidates = [downloadsRoot, localRootURL]
        return candidates.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }

    static func contents(of dir: URL) -> [URL] {
        let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        return urls.sorted { a, b in
            let aDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let bDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if aDir != bDir { return aDir }
            return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
    }

    static func itemType(of url: URL) -> RemoteItem.EntryType {
        ((try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false) ? .directory : .file
    }

    static func fileSize(of url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
    }

    static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    @discardableResult
    static func deleteLocal(url: URL) -> Bool {
        (try? fm.removeItem(at: url)) != nil
    }

    @discardableResult
    static func createDirectory(name: String, in parent: URL) -> Bool {
        guard !name.isEmpty else { return false }
        let dir = parent.appendingPathComponent(name, isDirectory: true)
        return (try? fm.createDirectory(at: dir, withIntermediateDirectories: false)) != nil
    }

    /// 生成不冲突的目标 URL（重名时加 (1)）
    static func uniqueDestination(for proposed: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: proposed.path) else { return proposed }
        let dir = proposed.deletingLastPathComponent()
        let ext = proposed.pathExtension
        let base = proposed.deletingPathExtension().lastPathComponent
        var idx = 1
        while true {
            let name = ext.isEmpty ? "\(base) (\(idx))" : "\(base) (\(idx)).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            idx += 1
        }
    }
}
