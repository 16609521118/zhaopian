import Foundation

enum MountError: LocalizedError {
    case invalidURL
    case connectionFailed(String)
    case authenticationFailed
    case notConnected
    case notFound(String)
    case serverError(Int, String)
    case unsupportedOperation(String)
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "地址无效，请检查 IP / 端口 / 路径"
        case .connectionFailed(let detail):
            return "连接失败：\(detail)"
        case .authenticationFailed:
            return "认证失败，请检查用户名 / 密码"
        case .notConnected:
            return "尚未建立连接"
        case .notFound(let name):
            return "找不到项目：\(name)"
        case .serverError(let code, let detail):
            return "服务器错误（\(code)）：\(detail)"
        case .unsupportedOperation(let name):
            return "该服务器不支持操作：\(name)"
        case .cancelled:
            return "已取消"
        case .unknown(let detail):
            return "发生错误：\(detail)"
        }
    }
}

/// 远程文件系统协议抽象：SMB 与 WebDAV 统一实现。
protocol RemoteFileSystem: AnyObject {
    /// 建立连接并验证凭据
    func connect() async throws
    func disconnect()

    /// 列出目录内容（按名称排序）
    func listDirectory(at path: String) async throws -> [RemoteItem]

    /// 下载文件到本地
    func download(path: String, to localURL: URL,
                  progress: @escaping (Int64, Int64) -> Void) async throws

    /// 上传本地文件到远程
    func upload(from localURL: URL, to path: String,
                progress: @escaping (Int64, Int64) -> Void) async throws

    func createDirectory(at path: String) async throws
    func deleteItem(at path: String, isDirectory: Bool) async throws
    func renameItem(at path: String, to newName: String) async throws
    func moveItem(from path: String, to newPath: String) async throws
}
