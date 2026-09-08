//
//  NativeMountViewController.swift
//  PhotoViewer
//
//  "添加 本地"挂载配置页：名称 / 备注 / 选择目录 / 挂载本地目录。
//  界面按设计稿还原：浅米色渐变背景、本地存储图标（浅灰圆角方块 + 黑色设备图案
//  + 右下角蓝色铅笔角标）、图标右侧"本地"标题与说明、白色圆角卡片、深色挂载按钮。
//  挂载采用 iOS 26 推荐的安全作用域书签方案（MountedFolderStore）：只保存授权书签、
//  原位枚举媒体元数据，不复制任何文件；文件由本地 HTTP 服务原位提供。
//  枚举在后台线程执行，避免大文件夹导致主线程卡死；失败信息通过 onError 回传网页。
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

    private static let mountButtonColor = UIColor(red: 50.0/255.0, green: 50.0/255.0, blue: 50.0/255.0, alpha: 1)
    private static let mountButtonDisabledColor = UIColor(white: 0.72, alpha: 1)

    private var selectedFolderURL: URL?

    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let iconContainer = UIView()
    private let driveIcon = UIImageView()
    private let editBadge = UIView()
    private let editPencil = UIImageView()
    private let localTitleLabel = UILabel()
    private let descLabel = UILabel()
    private let nameField = UITextField()
    private let noteField = UITextField()
    private let pathLabel = UILabel()
    private let chooseButton = UIButton(type: .system)
    private let hintLabel = UILabel()
    private let mountButton = UIButton(type: .system)

    private var backgroundGradient: CAGradientLayer?
    private var isMounting = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupBackground()
        setupUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backgroundGradient?.frame = view.bounds
    }

    // MARK: - 背景（浅米色渐变）

    private func setupBackground() {
        view.backgroundColor = UIColor(red: 0.937, green: 0.925, blue: 0.898, alpha: 1)
        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(red: 0.957, green: 0.949, blue: 0.925, alpha: 1).cgColor,
            UIColor(red: 0.910, green: 0.898, blue: 0.867, alpha: 1).cgColor
        ]
        gradient.locations = [0.0, 1.0]
        gradient.frame = view.bounds
        view.layer.insertSublayer(gradient, at: 0)
        backgroundGradient = gradient
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

        // 本地存储图标：浅灰圆角方块 + 黑色存储图案 + 右下角蓝色铅笔角标
        iconContainer.backgroundColor = UIColor(white: 0.925, alpha: 1)
        iconContainer.layer.cornerRadius = 20
        iconContainer.layer.shadowColor = UIColor.black.cgColor
        iconContainer.layer.shadowOpacity = 0.06
        iconContainer.layer.shadowOffset = CGSize(width: 0, height: 2)
        iconContainer.layer.shadowRadius = 6

        driveIcon.image = UIImage(systemName: "internaldrive")
        driveIcon.tintColor = UIColor(white: 0.12, alpha: 1)
        driveIcon.contentMode = .scaleAspectFit

        editBadge.backgroundColor = UIColor(red: 11.0/255.0, green: 132.0/255.0, blue: 255.0/255.0, alpha: 1)
        editBadge.layer.cornerRadius = 11
        editBadge.clipsToBounds = true

        editPencil.image = UIImage(systemName: "pencil")
        editPencil.tintColor = .white
        editPencil.contentMode = .scaleAspectFit

        // 标题 + 说明（图标右侧）
        localTitleLabel.text = "本地"
        localTitleLabel.font = .systemFont(ofSize: 21, weight: .semibold)
        localTitleLabel.textColor = .label

        descLabel.text = "iPhone 本机或 iCloud 云盘中的文件夹"
        descLabel.font = .systemFont(ofSize: 13)
        descLabel.textColor = .secondaryLabel
        descLabel.numberOfLines = 2

        let textStack = UIStackView(arrangedSubviews: [localTitleLabel, descLabel])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 5

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

        hintLabel.text = "可选择“我的 iPhone”或 iCloud 云盘中的文件夹。"
        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.textColor = .secondaryLabel
        hintLabel.numberOfLines = 0

        mountButton.setTitle("挂载本地目录", for: .normal)
        mountButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        mountButton.setTitleColor(.white, for: .normal)
        mountButton.backgroundColor = Self.mountButtonColor
        mountButton.layer.cornerRadius = 14
        mountButton.addTarget(self, action: #selector(mountTapped), for: .touchUpInside)

        // 布局
        [closeButton, titleLabel, iconContainer, driveIcon, editBadge, editPencil, textStack, card, hintLabel, mountButton].forEach {
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

            // 图标区
            iconContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            iconContainer.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 30),
            iconContainer.widthAnchor.constraint(equalToConstant: 84),
            iconContainer.heightAnchor.constraint(equalToConstant: 84),

            driveIcon.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor, constant: 14),
            driveIcon.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: -14),
            driveIcon.topAnchor.constraint(equalTo: iconContainer.topAnchor, constant: 14),
            driveIcon.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: -14),

            editBadge.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: -2),
            editBadge.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: -2),
            editBadge.widthAnchor.constraint(equalToConstant: 22),
            editBadge.heightAnchor.constraint(equalToConstant: 22),

            editPencil.centerXAnchor.constraint(equalTo: editBadge.centerXAnchor),
            editPencil.centerYAnchor.constraint(equalTo: editBadge.centerYAnchor),
            editPencil.widthAnchor.constraint(equalToConstant: 12),
            editPencil.heightAnchor.constraint(equalToConstant: 12),

            // 标题 + 说明（图标右侧，垂直居中）
            textStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 16),
            textStack.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),

            // 表单卡片
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: 30),
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
        // iOS 26 上 UIDocumentPickerViewController(forOpeningContentTypes:) 存在系统缺陷：
        // "打开/选择"按钮无响应或置灰（Apple 论坛 806694/838148/772053，DTS 确认 iOS 26
        // 只对"应用可写"的目录启用打开）。改用旧版 API（deprecated 但可用），走不同系统路径，
        // 行为一致：返回安全作用域 URL，可生成书签。
        let picker = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open)
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

        let folderId = "mnt-" + String(Int(Date().timeIntervalSince1970 * 1000))
        let folderName = nameField.text?.trimmingCharacters(in: .whitespaces) ?? "本地"

        setMounting(true)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 1) 保存安全作用域书签（只记授权、不复制任何文件）
            do {
                try MountedFolderStore.shared.add(folderId: folderId, name: folderName, from: sourceURL)
            } catch {
                DispatchQueue.main.async {
                    self.setMounting(false)
                    self.reportError("无法保存文件夹访问授权：\(error.localizedDescription)")
                }
                return
            }

            // 2) 原位枚举媒体元数据（后台线程，不复制）
            let items = Self.enumerateMediaMetadata(folderURL: sourceURL)

            DispatchQueue.main.async {
                self.setMounting(false)
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

    /// 原位枚举文件夹中的媒体文件元数据（名称/相对路径/类型/大小），不复制文件。
    private static func enumerateMediaMetadata(folderURL: URL) -> [[String: Any]] {
        let fm = FileManager.default
        let accessing = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        var items: [[String: Any]] = []
        guard let enumerator = fm.enumerator(at: folderURL,
                                             includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                             options: [.skipsHiddenFiles]) else {
            return items
        }
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            let filename = fileURL.lastPathComponent
            guard isMediaFile(filename) else { continue }
            let rel = String(fileURL.path.dropFirst(folderURL.path.count).dropFirst())
            guard !rel.isEmpty else { continue }
            items.append([
                "id": rel,
                "name": filename,
                "path": rel,
                "type": isVideoFile(filename) ? "video" : "image",
                "size": values.fileSize ?? 0
            ])
        }
        return items
    }

    private func setMounting(_ mounting: Bool) {
        isMounting = mounting
        mountButton.isEnabled = !mounting
        mountButton.setTitle(mounting ? "正在挂载…" : "挂载本地目录", for: .normal)
        mountButton.backgroundColor = mounting ? Self.mountButtonDisabledColor : Self.mountButtonColor
        closeButton.isEnabled = !mounting
        chooseButton.isEnabled = !mounting
        nameField.isEnabled = !mounting
        noteField.isEnabled = !mounting
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

    private static func isMediaFile(_ name: String) -> Bool {
        let exts = ["jpg","jpeg","png","gif","webp","bmp","svg","heic","heif","mp4","mov","avi","mkv","webm","flv","wmv","m4v","3gp"]
        return exts.contains((name as NSString).pathExtension.lowercased())
    }

    private static func isVideoFile(_ name: String) -> Bool {
        let exts = ["mp4","mov","avi","mkv","webm","flv","wmv","m4v","3gp"]
        return exts.contains((name as NSString).pathExtension.lowercased())
    }
}
