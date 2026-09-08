//
//  NativeMountViewController.swift
//  PhotoViewer
//
//  "添加 本地"挂载配置页：名称 / 备注 / 选择目录 / 挂载本地目录。
//  选中文件夹后复制到 App 沙盒 Documents/Mounted/，经 localapp:// scheme 离线访问。
//  交互采用"选择目录 → 挂载"两步，避免系统文件夹选择器"点打开没反应"的困惑。
//  复制在后台线程执行，避免大文件夹导致主线程卡死被系统杀掉；
//  失败信息通过 onError 回传网页，用户能看到具体原因。
//

import UIKit
import UniformTypeIdentifiers

class NativeMountViewController: UIViewController, UIDocumentPickerDelegate {

    /// 挂载完成回调（payload 与网页 __nativeMountResult 入参一致）
    var onMount: (([String: Any]) -> Void)?
    /// 挂载失败回调（message 回传网页 __nativeMountError）
    var onError: ((String) -> Void)?
    /// 用户取消回调
    var onCancel: (() -> Void)?

    private var selectedFolderURL: URL?

    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let iconView = UIImageView()
    private let descLabel = UILabel()
    private let nameField = UITextField()
    private let noteField = UITextField()
    private let pathLabel = UILabel()
    private let chooseButton = UIButton(type: .system)
    private let hintLabel = UILabel()
    private let mountButton = UIButton(type: .system)

    private var isMounting = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.949, green: 0.949, blue: 0.965, alpha: 1)
        setupUI()
    }

    // MARK: - UI

    private func makeFieldLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 16)
        l.textColor = .label
        return l
    }

    private func setupUI() {
        // 顶部：关闭 + 标题
        closeButton.setTitle("✕", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        closeButton.setTitleColor(.systemBlue, for: .normal)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        titleLabel.text = "添加 本地"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center

        // 说明区
        iconView.image = UIImage(systemName: "folder.fill")
        iconView.tintColor = .systemBlue
        iconView.contentMode = .scaleAspectFit

        descLabel.text = "iPhone本机或iCloud云盘中的文件夹"
        descLabel.font = .systemFont(ofSize: 13)
        descLabel.textColor = .secondaryLabel
        descLabel.textAlignment = .center

        // 表单卡片
        let card = UIView()
        card.backgroundColor = .white
        card.layer.cornerRadius = 12

        nameField.placeholder = "名称"
        nameField.text = "本地"
        nameField.font = .systemFont(ofSize: 16)
        nameField.textAlignment = .right
        nameField.returnKeyType = .done

        noteField.placeholder = "到期时间、账号归属…"
        noteField.font = .systemFont(ofSize: 16)
        noteField.textAlignment = .right
        noteField.returnKeyType = .done

        pathLabel.text = "我的 iPhone"
        pathLabel.font = .systemFont(ofSize: 16)
        pathLabel.textColor = .label
        pathLabel.textAlignment = .right
        pathLabel.numberOfLines = 2

        chooseButton.setTitle("选择目录", for: .normal)
        chooseButton.titleLabel?.font = .systemFont(ofSize: 16)
        chooseButton.setTitleColor(.systemBlue, for: .normal)
        chooseButton.addTarget(self, action: #selector(chooseTapped), for: .touchUpInside)

        hintLabel.text = "可选择“我的 iPhone”或iCloud云盘中的文件夹。"
        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.textColor = .secondaryLabel
        hintLabel.numberOfLines = 0

        mountButton.setTitle("挂载本地目录", for: .normal)
        mountButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        mountButton.setTitleColor(.white, for: .normal)
        mountButton.backgroundColor = .systemBlue
        mountButton.layer.cornerRadius = 14
        mountButton.addTarget(self, action: #selector(mountTapped), for: .touchUpInside)

        // 布局
        [closeButton, titleLabel, iconView, descLabel, card, hintLabel, mountButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        [nameField, noteField, pathLabel, chooseButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview($0)
        }
        let nameLabel = makeFieldLabel("名称")
        let noteLabel = makeFieldLabel("备注")
        let mountLabel = makeFieldLabel("挂载目录")
        [nameLabel, noteLabel, mountLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview($0)
        }

        let sep1 = makeSeparator()
        let sep2 = makeSeparator()
        card.addSubview(sep1)
        card.addSubview(sep2)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),

            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 30),
            iconView.widthAnchor.constraint(equalToConstant: 84),
            iconView.heightAnchor.constraint(equalToConstant: 84),

            descLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            descLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),

            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 28),
            card.heightAnchor.constraint(equalToConstant: 3 * 56 + 2),

            nameLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            nameLabel.centerYAnchor.constraint(equalTo: nameField.centerYAnchor),
            nameLabel.widthAnchor.constraint(equalToConstant: 64),

            nameField.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            nameField.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            nameField.topAnchor.constraint(equalTo: card.topAnchor),
            nameField.heightAnchor.constraint(equalToConstant: 56),

            noteLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            noteLabel.centerYAnchor.constraint(equalTo: noteField.centerYAnchor),
            noteLabel.widthAnchor.constraint(equalToConstant: 64),

            noteField.leadingAnchor.constraint(equalTo: noteLabel.trailingAnchor, constant: 8),
            noteField.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            noteField.topAnchor.constraint(equalTo: nameField.bottomAnchor),
            noteField.heightAnchor.constraint(equalToConstant: 56),

            mountLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            mountLabel.centerYAnchor.constraint(equalTo: pathLabel.centerYAnchor),
            mountLabel.widthAnchor.constraint(equalToConstant: 64),

            pathLabel.leadingAnchor.constraint(equalTo: mountLabel.trailingAnchor, constant: 8),
            pathLabel.trailingAnchor.constraint(equalTo: chooseButton.leadingAnchor, constant: -8),
            pathLabel.topAnchor.constraint(equalTo: noteField.bottomAnchor),
            pathLabel.heightAnchor.constraint(equalToConstant: 56),

            chooseButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            chooseButton.centerYAnchor.constraint(equalTo: pathLabel.centerYAnchor),
            chooseButton.widthAnchor.constraint(equalToConstant: 72),

            sep1.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            sep1.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            sep1.topAnchor.constraint(equalTo: nameField.bottomAnchor),
            sep1.heightAnchor.constraint(equalToConstant: 0.5),

            sep2.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            sep2.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            sep2.topAnchor.constraint(equalTo: noteField.bottomAnchor),
            sep2.heightAnchor.constraint(equalToConstant: 0.5),

            hintLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 4),
            hintLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -4),
            hintLabel.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 10),

            mountButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            mountButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            mountButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            mountButton.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    private func makeSeparator() -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1)
        return v
    }

    // MARK: - 交互

    @objc private func closeTapped() {
        guard !isMounting else { return }
        onCancel?()
        dismiss(animated: true)
    }

    @objc private func chooseTapped() {
        guard !isMounting else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @objc private func mountTapped() {
        guard !isMounting else { return }
        guard let url = selectedFolderURL else {
            showAlert("请先选择目录")
            return
        }
        mountFolder(from: url)
    }

    // MARK: - UIDocumentPickerDelegate

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        selectedFolderURL = url
        let name = url.lastPathComponent
        pathLabel.text = "我的 iPhone/\(name)"
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // 未选择目录，保持原样
    }

    // MARK: - 挂载执行

    private func mountFolder(from sourceURL: URL) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDir), isDir.boolValue else {
            reportError("所选目录无效，请重新选择")
            return
        }

        // 进入安全作用域（安全作用域是进程级的，在后台线程同样有效）
        let accessing = sourceURL.startAccessingSecurityScopedResource()

        let folderId = "mnt-" + String(Int(Date().timeIntervalSince1970 * 1000))
        let destRoot = LocalFileSchemeHandler.mountedRoot.appendingPathComponent(folderId, isDirectory: true)
        let folderName = nameField.text?.trimmingCharacters(in: .whitespaces) ?? "本地"

        // 挂载中状态：禁用交互，避免重复触发
        isMounting = true
        mountButton.isEnabled = false
        mountButton.setTitle("正在挂载…", for: .normal)
        mountButton.backgroundColor = .systemGray
        closeButton.isEnabled = false
        chooseButton.isEnabled = false
        nameField.isEnabled = false
        noteField.isEnabled = false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var items: [[String: Any]] = []
            var failed = 0
            var lastError = ""

            do {
                try fm.createDirectory(at: destRoot, withIntermediateDirectories: true)
                if let enumerator = fm.enumerator(at: sourceURL,
                                                  includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                  options: [.skipsHiddenFiles]) {
                    for case let fileURL as URL in enumerator {
                        // 单个文件失败不中断整个挂载
                        do {
                            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                            guard values.isRegularFile == true else { continue }
                            let filename = fileURL.lastPathComponent
                            guard Self.isMediaFile(filename) else { continue }
                            let rel = String(fileURL.path.dropFirst(sourceURL.path.count).dropFirst())
                            guard !rel.isEmpty else { continue }
                            let dest = destRoot.appendingPathComponent(rel)
                            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                            if fm.fileExists(atPath: dest.path) {
                                try? fm.removeItem(at: dest)
                            }
                            do {
                                try fm.copyItem(at: fileURL, to: dest)
                            } catch {
                                failed += 1
                                lastError = error.localizedDescription
                                continue
                            }
                            items.append([
                                "id": rel,
                                "name": filename,
                                "url": "localapp://media/\(folderId)/\(Self.encodePath(rel))",
                                "type": Self.isVideoFile(filename) ? "video" : "image",
                                "size": values.fileSize ?? 0
                            ])
                        } catch {
                            failed += 1
                            lastError = error.localizedDescription
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.finishMount(accessing: accessing, error: "无法创建挂载目录：\(error.localizedDescription)")
                }
                return
            }

            if accessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isMounting = false
                self.mountButton.isEnabled = true
                self.mountButton.setTitle("挂载本地目录", for: .normal)
                self.mountButton.backgroundColor = .systemBlue
                self.closeButton.isEnabled = true
                self.chooseButton.isEnabled = true
                self.nameField.isEnabled = true
                self.noteField.isEnabled = true

                if items.isEmpty {
                    if failed > 0 {
                        self.reportError("无法读取所选文件夹中的图片或视频（\(failed) 个文件读取失败，\(lastError)）")
                    } else {
                        // 目录里没有媒体文件：正常回调，网页会提示"未找到图片或视频"
                        self.onMount?([
                            "folderId": folderId,
                            "name": folderName.isEmpty ? "本地" : folderName,
                            "items": []
                        ])
                        self.dismiss(animated: true)
                    }
                    return
                }

                let payload: [String: Any] = [
                    "folderId": folderId,
                    "name": folderName.isEmpty ? "本地" : folderName,
                    "items": items
                ]
                self.onMount?(payload)
                self.dismiss(animated: true)
            }
        }
    }

    private func finishMount(accessing: Bool, error: String) {
        if accessing {
            selectedFolderURL?.stopAccessingSecurityScopedResource()
        }
        isMounting = false
        mountButton.isEnabled = true
        mountButton.setTitle("挂载本地目录", for: .normal)
        mountButton.backgroundColor = .systemBlue
        closeButton.isEnabled = true
        chooseButton.isEnabled = true
        nameField.isEnabled = true
        noteField.isEnabled = true
        reportError(error)
    }

    private func reportError(_ message: String) {
        onError?(message)
        showAlert(message)
    }

    // MARK: - 工具

    private func showAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private static func encodePath(_ rel: String) -> String {
        let parts = rel.split(separator: "/", omittingEmptySubsequences: false)
        return parts.map { $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? String($0) }.joined(separator: "/")
    }

    private static func isMediaFile(_ name: String) -> Bool {
        let exts = ["jpg","jpeg","png","gif","webp","bmp","svg","heic","heif","mp4","mov","avi","mkv","webm","flv","wmv","m4v","3gp"]
        return exts.contains((name as NSString).pathExtension.lowercased())
    }

    private static func isVideoFile(_ name: String) -> Bool {
        let exts = ["mp4","mov","avi","mkv","webm","flv","wmv","m4v","3gp"]
        return exts.contains((name as NSString).pathExtension.lowercased())
    }
}
