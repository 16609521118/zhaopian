import Foundation
import Combine

/// 挂载点列表的持久化存储（JSON 文件，密码除外）。
final class MountStore: ObservableObject {
    @Published private(set) var mounts: [Mount] = []

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("mounts.json")
    }

    init() {
        load()
    }

    // MARK: - CRUD

    func add(_ mount: Mount) {
        mounts.append(mount)
        save()
    }

    func update(_ mount: Mount) {
        guard let idx = mounts.firstIndex(where: { $0.id == mount.id }) else { return }
        mounts[idx] = mount
        save()
    }

    @discardableResult
    func delete(_ mount: Mount) -> Bool {
        mounts.removeAll { $0.id == mount.id }
        KeychainHelper.delete(for: mount.keychainAccount)
        save()
        return true
    }

    func mount(id: UUID) -> Mount? {
        mounts.first { $0.id == id }
    }

    func password(for mount: Mount) -> String? {
        KeychainHelper.password(for: mount.keychainAccount)
    }

    func savePassword(_ password: String, for mount: Mount) {
        KeychainHelper.save(password: password, for: mount.keychainAccount)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Mount].self, from: data) {
            mounts = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(mounts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
