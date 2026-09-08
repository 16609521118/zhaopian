//
//  NativeMountViewController.swift
//  PhotoViewer
//
//  "添加 本地"挂载配置页：支持两种挂载方式
//   1. 本机目录：选择 iPhone / iCloud 文件夹，复制到 App 沙盒离线访问
//   2. IP 映射：输入局域网地址（WebDAV / HTTP 目录 / 单个文件），在线直读不拷贝
//

import UIKit
import UniformTypeIdentifiers

class NativeMountViewController: UIViewController, UIDocumentPickerDelegate {

    /// 挂载完成回调（payload 与网页 __nativeMountResult 入参一致）
    var onMount: (([String: Any]) -> Void)?
    /// 用户取消回调
    var onCancel: (() -> Void)?

    private enum MountMode: Int {
        case localFolder = 0
        case ipMapping = 1
    }
    private var mode: MountMode = .localFolder

    private var selectedFolderURL: URL?

    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let modeControl = UISegmentedControl(items: ["本机目录", "IP 映射"])
    private let iconView = UIImageView()
    private let descLabel = UILabel()

    // 本机目录模式控件
    private let localCard = UIView()
    private let nameField = UITextField()
    private let noteField = UITextField()
    private let pathLabel = UILabel()
    private let chooseButton = UIButton(type: .system)

    // IP 映射模式控件
    private let ipCard = UIView()
    private let ipField = UITextField()
    private let ipHintLabel = UILabel()

    private let hintLabel = UILabel()
    private let mountButton = UIButton(type: .system)
    private var hintTopConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.949, green: 0.949, blue: 0.965, alpha: 1)
        setupUI()
        updateModeUI()
    }

    // MARK: - UI

    private func makeFieldLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 16)
        l.textColor = .label
        return l
    }

    private func makeSeparator() -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1)
        return v
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

        // 类型切换
        modeControl.selectedSegmentIndex = 0
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        // 说明区
        iconView.image = UIImage(systemName: "folder.fill")
        iconView.tintColor = .systemBlue
        iconView.contentMode = .scaleAspectFit

        descLabel.text = "iPhone本机或iCloud云盘中的文件夹"
        descLabel.font = .systemFont(ofSize: 13)
        descLabel.textColor = .secondaryLabel
        descLabel.textAlignment = .center

        // ===== 本机目录卡片 =====
        localCard.backgroundColor = .white
        localCard.layer.cornerRadius = 12

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

        // ===== IP 映射卡片 =====
        ipCard.backgroundColor = .white
        ipCard.layer.cornerRadius = 12

        ipField.placeholder = "http://192.168.1.100:8000/照片"
        ipField.font = .systemFont(ofSize: 15)
        ipField.autocapitalizationType = .none
        ipField.autocorrectionType = .no
        ipField.keyboardType = .URL
        ipField.returnKeyType = .done

        ipHintLabel.text = "支持 WebDAV（NAS）、HTTP 目录列表（电脑共享）、单个文件直链"
        ipHintLabel.font = .systemFont(ofSize: 12)
        ipHintLabel.textColor = .secondaryLabel
        ipHintLabel.numberOfLines = 0

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
        [closeButton, titleLabel, modeControl, iconView, descLabel, localCard, ipCard, hintLabel, mountButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        [nameField, noteField, pathLabel, chooseButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            localCard.addSubview($0)
        }
        [ipField, ipHintLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            ipCard.addSubview($0)
        }
        let nameLabel = makeFieldLabel("名称")
        let noteLabel = makeFieldLabel("备注")
        let mountLabel = makeFieldLabel("挂载目录")
        [nameLabel, noteLabel, mountLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            localCard.addSubview($0)
        }
        let sep1 = makeSeparator()
        let sep2 = makeSeparator()
        localCard.addSubview(sep1)
        localCard.addSubview(sep2)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),

            modeControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            modeControl.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 10),
            modeControl.widthAnchor.constraint(equalToConstant: 260),

            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 18),
            iconView.widthAnchor.constraint(equalToConstant: 72),
            iconView.heightAnchor.constraint(equalToConstant: 72),

            descLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            descLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 10),

            // 本机目录卡片
            localCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            localCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            localCard.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 24),
            localCard.heightAnchor.constraint(equalToConstant: 3 * 56 + 2),

            nameLabel.leadingAnchor.constraint(equalTo: localCard.leadingAnchor, constant: 16),
            nameLabel.centerYAnchor.constraint(equalTo: nameField.centerYAnchor),
            nameLabel.widthAnchor.constraint(equalToConstant: 64),

            nameField.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            nameField.trailingAnchor.constraint(equalTo: localCard.trailingAnchor, constant: -16),
            nameField.topAnchor.constraint(equalTo: localCard.topAnchor),
            nameField.heightAnchor.constraint(equalToConstant: 56),

            noteLabel.leadingAnchor.constraint(equalTo: localCard.leadingAnchor, constant: 16),
            noteLabel.centerYAnchor.constraint(equalTo: noteField.centerYAnchor),
            noteLabel.widthAnchor.constraint(equalToConstant: 64),

            noteField.leadingAnchor.constraint(equalTo: noteLabel.trailingAnchor, constant: 8),
            noteField.trailingAnchor.constraint(equalTo: localCard.trailingAnchor, constant: -16),
            noteField.topAnchor.constraint(equalTo: nameField.bottomAnchor),
            noteField.heightAnchor.constraint(equalToConstant: 56),

            mountLabel.leadingAnchor.constraint(equalTo: localCard.leadingAnchor, constant: 16),
            mountLabel.centerYAnchor.constraint(equalTo: pathLabel.centerYAnchor),
            mountLabel.widthAnchor.constraint(equalToConstant: 64),

            pathLabel.leadingAnchor.constraint(equalTo: mountLabel.trailingAnchor, constant: 8),
            pathLabel.trailingAnchor.constraint(equalTo: chooseButton.leadingAnchor, constant: -8),
            pathLabel.topAnchor.constraint(equalTo: noteField.bottomAnchor),
            pathLabel.heightAnchor.constraint(equalToConstant: 56),

            chooseButton.trailingAnchor.constraint(equalTo: localCard.trailingAnchor, constant: -16),
            chooseButton.centerYAnchor.constraint(equalTo: pathLabel.centerYAnchor),
            chooseButton.widthAnchor.constraint(equalToConstant: 72),

            sep1.leadingAnchor.constraint(equalTo: localCard.leadingAnchor, constant: 16),
            sep1.trailingAnchor.constraint(equalTo: localCard.trailingAnchor, constant: -16),
            sep1.topAnchor.constraint(equalTo: nameField.bottomAnchor),
            sep1.heightAnchor.constraint(equalToConstant: 0.5),

            sep2.leadingAnchor.constraint(equalTo: localCard.leadingAnchor, constant: 16),
            sep2.trailingAnchor.constraint(equalTo: localCard.trailingAnchor, constant: -16),
            sep2.topAnchor.constraint(equalTo: noteField.bottomAnchor),
            sep2.heightAnchor.constraint(equalToConstant: 0.5),

            // IP 映射卡片
            ipCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            ipCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            ipCard.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 24),
            ipCard.heightAnchor.constraint(equalToConstant: 110),

            ipField.leadingAnchor.constraint(equalTo: ipCard.leadingAnchor, constant: 16),
            ipField.trailingAnchor.constraint(equalTo: ipCard.trailingAnchor, constant: -16),
            ipField.topAnchor.constraint(equalTo: ipCard.topAnchor),
            ipField.heightAnchor.constraint(equalToConstant: 56),

            ipHintLabel.leadingAnchor.constraint(equalTo: ipCard.leadingAnchor, constant: 16),
            ipHintLabel.trailingAnchor.constraint(equalTo: ipCard.trailingAnchor, constant: -16),
            ipHintLabel.topAnchor.constraint(equalTo: ipField.bottomAnchor, constant: 6),

            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            mountButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            mountButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            mountButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            mountButton.heightAnchor.constraint(equalToConstant: 52),
        ])

        // hint 顶部约束随模式切换
        hintTopConstraint = hintLabel.topAnchor.constraint(equalTo: localCard.bottomAnchor, constant: 10)
        hintTopConstraint?.isActive = true
    }

    private func updateModeUI() {
        let isLocal = (mode == .localFolder)
        localCard.isHidden = !isLocal
        ipCard.isHidden = isLocal
        descLabel.text = isLocal ? "iPhone本机或iCloud云盘中的文件夹" : "通过局域网 IP 访问远端文件夹"
        hintLabel.text = isLocal
            ? "可选择“我的 iPhone”或iCloud云盘中的文件夹。"
            : "连接局域网内电脑 / NAS 的照片视频文件夹，在线浏览不占手机空间。"
        hintTopConstraint?.isActive = false
        hintTopConstraint = isLocal
            ? hintLabel.topAnchor.constraint(equalTo: localCard.bottomAnchor, constant: 10)
            : hintLabel.topAnchor.constraint(equalTo: ipCard.bottomAnchor, constant: 10)
        hintTopConstraint?.isActive = true
    }

    // MARK: - 交互

    @objc private func closeTapped() {
        onCancel?()
        dismiss(animated: true)
    }

    @objc private func modeChanged() {
        mode = MountMode(rawValue: modeControl.selectedSegmentIndex) ?? .localFolder
        view.endEditing(true)
        updateModeUI()
    }

    @objc private func chooseTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @objc private func mountTapped() {
        switch mode {
        case .localFolder:
            guard let url = selectedFolderURL else {
                showAlert("请先选择目录")
                return
            }
            mountFolder(from: url)
        case .ipMapping:
            mountIPMapping()
        }
    }

    // MARK: - UIDocumentPickerDelegate

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        selectedFolderURL = url
        let name = url.lastPathComponent
        pathLabel.text = "我的 iPhone/\(name)"
        _ = url.startAccessingSecurityScopedResource()
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // 未选择目录，保持原样
    }

    // MARK: - IP 映射挂载

    private func mountIPMapping() {
        let raw = ipField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else {
            showAlert("请输入局域网地址")
            return
        }
        var urlStr = raw
        if !urlStr.lowercased().hasPrefix("http://") && !urlStr.lowercased().hasPrefix("https://") {
            urlStr = "http://" + urlStr
        }
        guard let url = URL(string: urlStr) else {
            showAlert("地址格式不正确")
            return
        }

        mountButton.isEnabled = false
        mountButton.setTitle("正在连接…", for: .normal)

        RemoteMountScanner.scan(baseURL: url) { [weak self] items in
            guard let self = self else { return }
            self.mountButton.isEnabled = true
            self.mountButton.setTitle("挂载本地目录", for: .normal)

            guard let items = items else {
                self.showAlert("无法连接，请检查地址和网络（支持 WebDAV 或 HTTP 目录列表）")
                return
            }
            guard !items.isEmpty else {
                self.showAlert("该目录下没有找到图片或视频")
                return
            }

            let folderId = "ip-" + String(Int(Date().timeIntervalSince1970 * 1000))
            let folderName = self.ipField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "IP 映射"
            let payloadItems: [[String: Any]] = items.map { it in
                [
                    "id": it.relPath,
                    "name": it.name,
                    "url": it.url,
                    "type": it.type,
                    "size": it.size
                ]
            }
            let payload: [String: Any] = [
                "folderId": folderId,
                "name": folderName.isEmpty ? "IP 映射" : folderName,
                "items": payloadItems
            ]
            self.onMount?(payload)
            self.dismiss(animated: true)
        }
    }

    // MARK: - 本机目录挂载

    private func mountFolder(from sourceURL: URL) {
        let folderId = "mnt-" + String(Int(Date().timeIntervalSince1970 * 1000))
        let destRoot = LocalFileSchemeHandler.mountedRoot.appendingPathComponent(folderId, isDirectory: true)
        let fm = FileManager.default
        var isDir: ObjCBool = false

        guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDir), isDir.boolValue else {
            showAlert("所选目录无效，请重新选择")
            return
        }

        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        do {
            try fm.createDirectory(at: destRoot, withIntermediateDirectories: true)
            var items: [[String: Any]] = []
            if let enumerator = fm.enumerator(at: sourceURL, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    guard values.isRegularFile == true else { continue }
                    let filename = fileURL.lastPathComponent
                    guard Self.isMediaFile(filename) else { continue }
                    let rel = String(fileURL.path.dropFirst(sourceURL.path.count).dropFirst())
                    let dest = destRoot.appendingPathComponent(rel)
                    try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if fm.fileExists(atPath: dest.path) {
                        try? fm.removeItem(at: dest)
                    }
                    try fm.copyItem(at: fileURL, to: dest)
                    items.append([
                        "id": rel,
                        "name": filename,
                        "url": "localapp://media/\(folderId)/\(Self.encodePath(rel))",
                        "type": Self.isVideoFile(filename) ? "video" : "image",
                        "size": values.fileSize ?? 0
                    ])
                }
            }
            let folderName = nameField.text?.trimmingCharacters(in: .whitespaces) ?? "本地"
            let payload: [String: Any] = [
                "folderId": folderId,
                "name": folderName.isEmpty ? "本地" : folderName,
                "items": items
            ]
            onMount?(payload)
            dismiss(animated: true)
        } catch {
            showAlert("挂载失败：\(error.localizedDescription)")
        }
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
