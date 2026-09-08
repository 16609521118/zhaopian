import Foundation
import Combine

/// 文件浏览器状态：管理当前路径、目录内容与文件操作。
@MainActor
final class FileBrowserViewModel: ObservableObject {
    let mount: Mount
    let service: RemoteFileSystem
    let transferVM: TransferViewModel

    @Published var currentPath: String = "/"
    @Published private(set) var items: [RemoteItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    private var taskID = 0

    init(mount: Mount, service: RemoteFileSystem, transferVM: TransferViewModel) {
        self.mount = mount
        self.service = service
        self.transferVM = transferVM
    }

    var isAtRoot: Bool { currentPath == "/" }

    /// 面包屑（不含根）
    var pathComponents: [String] {
        guard currentPath != "/" else { return [] }
        return currentPath.split(separator: "/").map(String.init)
    }

    func push(_ name: String) {
        currentPath = RemoteItem.join(currentPath, name)
        Task { await refresh() }
    }

    func popToRoot() {
        currentPath = "/"
        Task { await refresh() }
    }

    func popTo(_ index: Int) {
        let comps = currentPath.split(separator: "/").map(String.init)
        guard index >= 0, index < comps.count else { popToRoot(); return }
        currentPath = "/" + comps[0...index].joined(separator: "/")
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await service.listDirectory(at: currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Operations

    func createDirectory(name: String) async {
        guard !name.isEmpty else { return }
        let path = RemoteItem.join(currentPath, name)
        do {
            try await service.createDirectory(at: path)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(_ item: RemoteItem, to newName: String) async {
        guard !newName.isEmpty, newName != item.name else { return }
        do {
            try await service.renameItem(at: item.path, to: newName)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func move(_ item: RemoteItem, to directory: String) async {
        guard directory != RemoteItem.parent(of: item.path) else { return }
        let newPath = RemoteItem.join(directory, item.name)
        do {
            try await service.moveItem(from: item.path, to: newPath)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ item: RemoteItem) async {
        do {
            try await service.deleteItem(at: item.path, isDirectory: item.isDirectory)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 下载到该挂载点的本地目录
    func download(_ item: RemoteItem) async {
        let localDir = LocalFileService.downloadDirectory(for: mount.localRootName)
        let proposed = localDir.appendingPathComponent(Formatters.safeFileName(item.name))
        let destination = LocalFileService.uniqueDestination(for: proposed)
        let task = TransferTask(
            mountName: mount.localRootName,
            direction: .download,
            remotePath: item.path,
            localPath: destination.path,
            totalBytes: item.size ?? 0
        )
        transferVM.enqueue(task, using: service)
    }

    /// 上传本地文件到当前目录
    func upload(url: URL) async {
        let destination = RemoteItem.join(currentPath, url.lastPathComponent)
        let task = TransferTask(
            mountName: mount.localRootName,
            direction: .upload,
            remotePath: destination,
            localPath: url.path,
            totalBytes: LocalFileService.fileSize(of: url) ?? 0
        )
        transferVM.enqueue(task, using: service)
    }
}
