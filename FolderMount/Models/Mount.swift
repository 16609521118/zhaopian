import Foundation

/// 一个挂载点：把一台局域网文件服务器上的共享目录映射到应用内。
struct Mount: Identifiable, Codable, Hashable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case smb = "SMB"
        case webdav = "WebDAV"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .smb: return "SMB（Windows / NAS / macOS 共享）"
            case .webdav: return "WebDAV（群晖 / Nextcloud / 自建）"
            }
        }

        var defaultPort: Int {
            switch self {
            case .smb: return 445
            case .webdav: return 5005
            }
        }
    }

    var id: UUID
    var name: String
    var kind: Kind
    /// 服务器 IP 或主机名，如 192.168.1.100
    var host: String
    var port: Int
    /// SMB：共享名（如 Music 或 Music/Sub）；WebDAV：服务器根路径（如 /dav 或留空）
    var path: String
    var username: String
    var isAnonymous: Bool
    /// 密码不参与 Codable，存于 Keychain（按 mount id）
    var lastConnectedAt: Date?
    /// 是否已在本会话中建立连接
    var isConnected: Bool
    var createdAt: Date

    init(id: UUID = UUID(), name: String = "", kind: Kind = .smb,
         host: String = "", port: Int? = nil, path: String = "",
         username: String = "", isAnonymous: Bool = false,
         lastConnectedAt: Date? = nil, isConnected: Bool = false,
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.kind = kind
        self.host = host
        self.port = port ?? kind.defaultPort
        self.path = path
        self.username = username
        self.isAnonymous = isAnonymous
        self.lastConnectedAt = lastConnectedAt
        self.isConnected = isConnected
        self.createdAt = createdAt
    }

    /// 挂载后的本地根目录（下载内容落在此目录）
    var localRootName: String {
        let safe = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return safe.isEmpty ? "\(kind.rawValue)-\(host)" : safe
    }

    /// 展示用地址：smb://host/share
    var displayAddress: String {
        switch kind {
        case .smb:
            return "smb://\(host)\(path.isEmpty ? "" : "/\(path)")"
        case .webdav:
            return "http(s)://\(host):\(port)\(path)"
        }
    }

    var displayDetail: String {
        var parts: [String] = []
        if !host.isEmpty { parts.append(host) }
        if !path.isEmpty { parts.append(path) }
        let addr = parts.joined(separator: " / ")
        let user = isAnonymous ? "匿名" : username
        return addr.isEmpty ? "未配置地址" : "\(addr) · \(user)"
    }

    /// 统一供 Keychain 使用的账户名
    var keychainAccount: String { "mount-\(id.uuidString)" }
}
