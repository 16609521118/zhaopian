import Foundation
import AMSMB2

/// SMB 协议实现（基于 AMSMB2 / libsmb2）。
/// 支持连接 Windows 共享、NAS（群晖 / 威联通 / OpenMediaVault 等）、macOS 共享。
final class SMBService: RemoteFileSystem {
    private let mount: Mount
    private let password: String?
    private var client: AMSMB2?

    init(mount: Mount, password: String?) {
        self.mount = mount
        self.password = password
    }

    // MARK: - Path helpers

    /// 把应用内路径（/ 开头）转换为 AMSMB2 路径：/share/rest
    private func smbPath(_ path: String) -> String {
        let share = mount.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let rest = path.hasPrefix("/") ? String(path.dropFirst()) : path
        if share.isEmpty { return "/" + rest }
        if rest.isEmpty { return "/" + share }
        return "/" + share + "/" + rest
    }

    private func appPath(from smb: String) -> String {
        let share = mount.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !share.isEmpty else { return smb }
        guard smb.hasPrefix("/\(share)") else { return smb }
        let rest = String(smb.dropFirst(share.count + 1))
        return rest.isEmpty ? "/" : "/" + rest
    }

    // MARK: - RemoteFileSystem

    func connect() async throws {
        let configuration = SMBConfiguration()
        // 缩短超时，避免内网不可达时长时间等待
        configuration.timeout = 15
        let client = AMSMB2(configuration: configuration)
        let username = mount.isAnonymous ? "guest" : mount.username
        let password = mount.isAnonymous ? "" : (self.password ?? "")

        let connected: Bool = try await withCheckedThrowingContinuation { continuation in
            client.connect(host: mount.host, port: UInt16(mount.port),
                           username: username, password: password) { result in
                switch result {
                case .success(let ok):
                    continuation.resume(returning: ok)
                case .failure(let error):
                    continuation.resume(throwing: self.mapError(error))
                }
            }
        }
        guard connected else {
            throw MountError.connectionFailed("服务器拒绝连接")
        }
        self.client = client

        // 用一次目录列举验证凭据与共享可用
        _ = try await listDirectory(at: "/")
    }

    func disconnect() {
        guard let client else { return }
        client.disconnect { _ in }
        self.client = nil
    }

    func listDirectory(at path: String) async throws -> [RemoteItem] {
        guard let client else { throw MountError.notConnected }
        let files: [SMBFile] = try await withCheckedThrowingContinuation { continuation in
            client.listDirectory(atPath: smbPath(path)) { result in
                switch result {
                case .success(let list):
                    continuation.resume(returning: list)
                case .failure(let error):
                    continuation.resume(throwing: self.mapError(error))
                }
            }
        }
        return files.compactMap { file in
            guard !file.name.isEmpty, file.name != ".", file.name != ".." else { return nil }
            let appPath = self.appPath(from: self.smbPath(RemoteItem.join(path, file.name)))
            return RemoteItem(
                name: file.name,
                path: appPath,
                type: file.isDirectory ? .directory : .file,
                size: file.isDirectory ? nil : file.fileSize,
                modifiedAt: file.modificationDate
            )
        }
    }

    func download(path: String, to localURL: URL,
                  progress: @escaping (Int64, Int64) -> Void) async throws {
        guard let client else { throw MountError.notConnected }
        let result: Bool = try await withCheckedThrowingContinuation { continuation in
            client.download(path: smbPath(path), to: localURL,
                            progress: { transferred, total in
                progress(transferred, total)
            }) { result in
                switch result {
                case .success(let ok):
                    continuation.resume(returning: ok)
                case .failure(let error):
                    try? FileManager.default.removeItem(at: localURL)
                    continuation.resume(throwing: self.mapError(error))
                }
            }
        }
        guard result else {
            try? FileManager.default.removeItem(at: localURL)
            throw MountError.unknown("下载失败")
        }
    }

    func upload(from localURL: URL, to path: String,
                progress: @escaping (Int64, Int64) -> Void) async throws {
        guard let client else { throw MountError.notConnected }
        let result: Bool = try await withCheckedThrowingContinuation { continuation in
            client.upload(from: localURL, to: smbPath(path),
                          progress: { transferred, total in
                progress(transferred, total)
            }) { result in
                switch result {
                case .success(let ok):
                    continuation.resume(returning: ok)
                case .failure(let error):
                    continuation.resume(throwing: self.mapError(error))
                }
            }
        }
        guard result else { throw MountError.unknown("上传失败") }
    }

    func createDirectory(at path: String) async throws {
        guard let client else { throw MountError.notConnected }
        let result: Bool = try await withCheckedThrowingContinuation { continuation in
            client.createDirectory(atPath: smbPath(path)) { result in
                switch result {
                case .success(let ok):
                    continuation.resume(returning: ok)
                case .failure(let error):
                    continuation.resume(throwing: self.mapError(error))
                }
            }
        }
        guard result else { throw MountError.unknown("创建目录失败") }
    }

    func deleteItem(at path: String, isDirectory: Bool) async throws {
        guard let client else { throw MountError.notConnected }
        let result: Bool = try await withCheckedThrowingContinuation { continuation in
            let handler: (Result<Bool, Error>) -> Void = { result in
                switch result {
                case .success(let ok):
                    continuation.resume(returning: ok)
                case .failure(let error):
                    continuation.resume(throwing: self.mapError(error))
                }
            }
            if isDirectory {
                client.deleteDirectory(atPath: self.smbPath(path), completion: handler)
            } else {
                client.deleteFile(atPath: self.smbPath(path), completion: handler)
            }
        }
        guard result else { throw MountError.unknown("删除失败") }
    }

    func renameItem(at path: String, to newName: String) async throws {
        guard let client else { throw MountError.notConnected }
        let newPath = RemoteItem.join(RemoteItem.parent(of: path), newName)
        let result: Bool = try await withCheckedThrowingContinuation { continuation in
            client.renameItem(atPath: smbPath(path), toPath: smbPath(newPath)) { result in
                switch result {
                case .success(let ok):
                    continuation.resume(returning: ok)
                case .failure(let error):
                    continuation.resume(throwing: self.mapError(error))
                }
            }
        }
        guard result else { throw MountError.unknown("重命名失败") }
    }

    func moveItem(from path: String, to newPath: String) async throws {
        guard let client else { throw MountError.notConnected }
        let result: Bool = try await withCheckedThrowingContinuation { continuation in
            client.moveItem(atPath: smbPath(path), toPath: smbPath(newPath)) { result in
                switch result {
                case .success(let ok):
                    continuation.resume(returning: ok)
                case .failure(let error):
                    continuation.resume(throwing: self.mapError(error))
                }
            }
        }
        guard result else { throw MountError.unknown("移动失败") }
    }

    // MARK: - Error mapping

    private func mapError(_ error: Error) -> Error {
        let nsError = error as NSError
        // AMSMB2 的错误描述通常已包含足够信息，按关键特征归类
        let desc = error.localizedDescription
        if desc.localizedCaseInsensitiveContains("auth") || desc.localizedCaseInsensitiveContains("登录") || desc.localizedCaseInsensitiveContains("credential") || nsError.code == -7 {
            return MountError.authenticationFailed
        }
        if desc.localizedCaseInsensitiveContains("not found") || desc.localizedCaseInsensitiveContains("不存在") {
            return MountError.notFound(desc)
        }
        if desc.localizedCaseInsensitiveContains("timeout") || desc.localizedCaseInsensitiveContains("超时") {
            return MountError.connectionFailed("连接超时，请检查 IP 与端口")
        }
        if desc.localizedCaseInsensitiveContains("denied") || desc.localizedCaseInsensitiveContains("拒绝") {
            return MountError.unknown("权限不足或共享不可用")
        }
        if let smbCode = (error as? AMSB2Error).map({ String(describing: $0) }), smbCode.contains("unexpectedStatusCode") {
            return MountError.serverError(-1, "SMB 服务器返回异常状态")
        }
        return MountError.connectionFailed(desc.isEmpty ? "未知网络错误" : desc)
    }
}
