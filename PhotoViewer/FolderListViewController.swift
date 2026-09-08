//
//  FolderListViewController.swift
//  PhotoViewer
//
//  已挂载文件夹列表。右上角 + 弹出系统文件选择器选择本地文件夹，
//  通过安全作用域书签真正挂载（原位访问，不复制）。
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

    // MARK: - 挂载文件夹

    @objc private func addTapped() {
        // 标准文件夹选择器：选择后返回安全作用域 URL，可生成书签持久访问。
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        do {
            let folder = try store.mount(url: url)
            tableView.reloadData()
            // 挂载成功后直接打开
            open(folder: folder)
        } catch {
            let alert = UIAlertController(
                title: "挂载失败",
                message: "无法保存文件夹访问授权：\(error.localizedDescription)",
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
            config.text = "暂无文件夹"
            config.secondaryText = "点右上角 + 挂载本地文件夹"
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
