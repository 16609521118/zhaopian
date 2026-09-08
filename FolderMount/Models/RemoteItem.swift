import Foundation

/// 协议无关的远程条目（目录 / 文件）。
struct RemoteItem: Identifiable, Equatable {
    enum EntryType {
        case directory
        case file
    }

    /// 当前目录下的名称
    var name: String
    /// 服务器上完整路径（以 / 分隔），如 /Music/Album
    var path: String
    var type: EntryType
    var size: Int64?
    var modifiedAt: Date?

    var id: String { path }

    var isDirectory: Bool { type == .directory }

    var displaySize: String {
        guard let size else { return "—" }
        return Formatters.fileSize(size)
    }

    var displayModified: String {
        guard let modifiedAt else { return "" }
        return Formatters.dateTime(modifiedAt)
    }

    /// 目录排在文件前，各自按名称排序
    static func sorted(_ items: [RemoteItem]) -> [RemoteItem] {
        items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// 拼接子路径
    static func join(_ base: String, _ name: String) -> String {
        if base == "/" || base.isEmpty { return "/" + name }
        return base + "/" + name
    }

    /// 取路径的父目录
    static func parent(of path: String) -> String {
        guard path != "/" else { return "/" }
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard let slash = trimmed.lastIndex(of: "/") else { return "/" }
        let parent = String(trimmed[..<slash])
        return parent.isEmpty ? "/" : parent
    }

    /// 路径的最后一段
    static func name(of path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard let slash = trimmed.lastIndex(of: "/") else { return trimmed }
        return String(trimmed[trimmed.index(after: slash)...])
    }
}
