import UIKit
import UniformTypeIdentifiers

/// 主界面：已挂载的本地文件夹列表
final class MountListViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyLabel = UILabel()
    private let emptyHint = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "本地文件夹"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add,
                                                            target: self,
                                                            action: #selector(addMountedFolder))
        setupTableView()
        setupEmptyState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        updateEmptyState()
    }

    private func setupTableView() {
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "folderCell")
    }

    private func setupEmptyState() {
        emptyLabel.text = "还没有挂载的文件夹"
        emptyLabel.font = .systemFont(ofSize: 17, weight: .medium)
        emptyLabel.textAlignment = .center

        emptyHint.text = "点右上角 + 添加本地文件夹\n（iCloud Drive / 我的 iPhone / 外接存储）"
        emptyHint.font = .systemFont(ofSize: 14)
        emptyHint.textColor = .secondaryLabel
        emptyHint.textAlignment = .center
        emptyHint.numberOfLines = 0

        view.addSubview(emptyLabel)
        view.addSubview(emptyHint)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyHint.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            emptyHint.topAnchor.constraint(equalTo: emptyLabel.bottomAnchor, constant: 8),
            emptyHint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyHint.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyHint.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
    }

    private func updateEmptyState() {
        let isEmpty = BookmarkStore.shared.folders.isEmpty
        emptyLabel.isHidden = !isEmpty
        emptyHint.isHidden = !isEmpty
        tableView.isHidden = isEmpty
    }

    @objc private func addMountedFolder() {
        // 与 SenPlayer 相同：调起系统文件选择器（文件夹模式）
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.delegate = self
        present(picker, animated: true)
    }

    private func showAlert(title: String, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource / UITableViewDelegate

extension MountListViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        BookmarkStore.shared.folders.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "folderCell", for: indexPath)
        let folder = BookmarkStore.shared.folders[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = folder.name
        config.secondaryText = folder.url.path
        config.image = UIImage(systemName: "folder")
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let folder = BookmarkStore.shared.folders[indexPath.row]
        let browser = FolderBrowserViewController(folder: folder, index: indexPath.row)
        navigationController?.pushViewController(browser, animated: true)
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle,
                   forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            BookmarkStore.shared.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            updateEmptyState()
        }
    }
}

// MARK: - UIDocumentPickerDelegate（挂载核心步骤）

extension MountListViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }

        // 1. 建立安全作用域访问
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }

        // 2. 在访问权有效期内生成书签并持久化
        guard let bookmark = SecurityScopedBookmark.make(for: url) else {
            showAlert(title: "挂载失败", message: "无法保存对该文件夹的访问权限，请重试。")
            return
        }
        BookmarkStore.shared.add(MountedFolder(url: url, bookmarkData: bookmark))
        tableView.reloadData()
        updateEmptyState()
    }
}
