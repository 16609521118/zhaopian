import Foundation
import Combine

/// 挂载列表页状态：管理连接会话（内存缓存已连接的 RemoteFileSystem）。
@MainActor
final class MountListViewModel: ObservableObject {
    @Published var isWorking = false
    @Published var errorMessage: String?

    /// 已连接的会话：mount id -> 文件系统服务
    private var sessions: [UUID: RemoteFileSystem] = [:]
    private var store: MountStore

    init(store: MountStore) {
        self.store = store
    }

    func isConnected(_ mount: Mount) -> Bool {
        sessions[mount.id] != nil
    }

    func session(for mount: Mount) -> RemoteFileSystem? {
        sessions[mount.id]
    }

    /// 连接（或复用已连接会话）。成功后返回会话。
    func connect(_ mount: Mount) async throws -> RemoteFileSystem {
        if let existing = sessions[mount.id] {
            return existing
        }
        let password = store.password(for: mount)
        let service: RemoteFileSystem
        switch mount.kind {
        case .smb:
            service = SMBService(mount: mount, password: password)
        case .webdav:
            service = WebDAVService(mount: mount, password: password)
        }
        do {
            try await service.connect()
            sessions[mount.id] = service
            var updated = mount
            updated.isConnected = true
            updated.lastConnectedAt = Date()
            store.update(updated)
            return service
        } catch {
            throw error
        }
    }

    func disconnect(_ mount: Mount) {
        sessions[mount.id]?.disconnect()
        sessions.removeValue(forKey: mount.id)
        var updated = mount
        updated.isConnected = false
        store.update(updated)
    }

    func disconnectAll() {
        for (_, service) in sessions { service.disconnect() }
        sessions.removeAll()
    }
}
