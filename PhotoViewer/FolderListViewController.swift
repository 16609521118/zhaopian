//
//  FolderListViewController.swift
//  PhotoViewer
//
//  已挂载文件夹列表。右上角 + 弹出系统文件选择器（多选模式），
//  进入目标文件夹后批量勾选照片/视频，逐文件书签挂载（原位访问，不复制）。
//  iOS 26 文件夹选择器有缺陷，故用文件多选替代。
//

import UIKit
import UniformTypeIdentifiers

final class FolderListViewController: UIViewController,
                                      UITableViewDataSource, UITableViewDelegate,
                                      UIDocumentPickerDelegate {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let store = FolderStore.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "照片查看器"
        view.backgroundColor = .systemGroupedBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(addTapped)
        )
        navigationItem.leftBarButtonItem = editButtonItem

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FolderCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    // MARK: - 挂载（文件多选模式）

    @objc private func addTapped() {
        // iOS 26 上文件夹选择器的"打开"按钮有系统缺陷，改用文件多选：
        // 用户进入目标文件夹后批量勾选照片/视频，App 逐文件书签挂载为一组。
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.image, .movie]
        )
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !urls.isEmpty else { return }
        do {
            let folder = try store.mount(urls: urls)
            tableView.reloadData()
            open(folder: folder)
        } catch {
            let alert = UIAlertController(
                title: "挂载失败",
                message: "无法保存文件访问授权：\(error.localizedDescription)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // 用户取消，无需处理
    }

    // MARK: - Table view

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return store.folders.isEmpty ? 1 : store.folders.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FolderCell", for: indexPath)
        var config = cell.defaultContentConfiguration()

        if store.folders.isEmpty {
            config.text = "暂无文件"
            config.secondaryText = "点右上角 +，进入文件夹后批量勾选照片/视频"
            config.textProperties.color = .secondaryLabel
            config.secondaryTextProperties.color = .tertiaryLabel
            cell.accessoryType = .none
            cell.selectionStyle = .none
        } else {
            let folder = store.folders[indexPath.row]
            let count = store.media(in: folder).count
            config.text = folder.name
            config.secondaryText = "\(count) 个项目"
            config.textProperties.color = .label
            config.secondaryTextProperties.color = .secondaryLabel
            config.image = UIImage(systemName: "folder.fill")
            config.imageProperties.tintColor = .systemBlue
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        }
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !store.folders.isEmpty else { return }
        open(folder: store.folders[indexPath.row])
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle,
                   forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, !store.folders.isEmpty else { return }
        let folder = store.folders[indexPath.row]
        store.unmount(id: folder.id)
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    private func open(folder: MountedFolder) {
        let grid = GridViewController(folder: folder)
        navigationController?.pushViewController(grid, animated: true)
    }
}
