import UIKit
import AVFoundation
import AVKit

/// 浏览已挂载文件夹的内容，点击视频直接播放
final class FolderBrowserViewController: UITableViewController {

    private let folder: MountedFolder
    private let index: Int

    /// 是否为根级浏览（只有根级负责 start/stop 安全作用域访问）
    private let ownsAccess: Bool
    private var isAccessing = false

    private var entries: [URL] = []
    private var subfolders: [URL] = []
    private var files: [URL] = []

    /// AVPlayer 可直接播放的格式（如需更多格式可扩展）
    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "3gp"]

    init(folder: MountedFolder, index: Int, ownsAccess: Bool = true) {
        self.folder = folder
        self.index = index
        self.ownsAccess = ownsAccess
        super.init(style: .insetGrouped)
    }

    /// 子文件夹浏览（继承父级的访问权，不单独管理 start/stop）
    init(subfolder url: URL, title: String) {
        self.folder = MountedFolder(url: url, bookmarkData: Data())
        self.index = -1
        self.ownsAccess = false
        super.init(style: .insetGrouped)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if title?.isEmpty != false {
            title = folder.name
        }
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "entryCell")
        loadEntries()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 若访问权曾被释放（例如弹出播放器后返回），重新建立
        if ownsAccess && !isAccessing {
            isAccessing = folder.url.startAccessingSecurityScopedResource()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 仅当真正从导航栈移除（返回列表）时释放访问权；
        // 进入子文件夹或弹出播放器时不释放，避免子路径读取失败
        if ownsAccess && isAccessing && isMovingFromParent {
            folder.url.stopAccessingSecurityScopedResource()
            isAccessing = false
        }
    }

    // MARK: - 挂载访问与目录枚举

    private func loadEntries() {
        var resolvedURL = folder.url

        if ownsAccess {
            // 解析书签；过期则顺手重建
            guard let (url, isStale) = SecurityScopedBookmark.resolve(folder.bookmarkData) else {
                showMountLostAlert()
                return
            }
            resolvedURL = url
            if isStale {
                if let fresh = SecurityScopedBookmark.make(for: url) {
                    var updated = folder
                    updated.url = url
                    updated.bookmarkData = fresh
                    BookmarkStore.shared.replace(updated, at: index)
                }
            }
            // 建立安全作用域访问（与 SenPlayer 挂载后读取文件同机制）
            isAccessing = resolvedURL.startAccessingSecurityScopedResource()
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        if let urls = try? FileManager.default.contentsOfDirectory(
            at: resolvedURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) {
            entries = urls.sorted {
                $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
            }
        }
        splitEntries()
        tableView.reloadData()
    }

    private func splitEntries() {
        subfolders = []
        files = []
        for url in entries {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                subfolders.append(url)
            } else {
                files.append(url)
            }
        }
    }

    private func showMountLostAlert() {
        let alert = UIAlertController(
            title: "挂载已失效",
            message: "该文件夹的访问权限已失效（重启设备或文件位置变化可能导致）。请返回列表删除后重新挂载。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "返回", style: .default) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    // MARK: - UITableViewDataSource / Delegate

    override func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "文件夹" : "文件"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? subfolders.count : files.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "entryCell", for: indexPath)
        let url = indexPath.section == 0 ? subfolders[indexPath.row] : files[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = url.lastPathComponent
        if indexPath.section == 0 {
            config.image = UIImage(systemName: "folder")
        } else {
            let isVideo = Self.videoExtensions.contains(url.pathExtension.lowercased())
            config.image = UIImage(systemName: isVideo ? "film" : "doc")
        }
        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            let url = subfolders[indexPath.row]
            let child = FolderBrowserViewController(subfolder: url, title: url.lastPathComponent)
            navigationController?.pushViewController(child, animated: true)
        } else {
            play(url: files[indexPath.row])
        }
    }

    // MARK: - 播放

    private func play(url: URL) {
        let asset = AVURLAsset(url: url)
        guard asset.isPlayable else {
            let alert = UIAlertController(title: "无法播放",
                                          message: "该文件格式不受系统播放器支持。",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
            return
        }
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        let playerVC = AVPlayerViewController()
        playerVC.player = player
        present(playerVC, animated: true) {
            player.play()
        }
    }
}
