//
//  ViewController.swift
//  PhotoViewer
//
//  iOS 26 架构主视图控制器：
//   - 本地回环 HTTP 服务（LocalHTTPServer）提供网页与媒体资源（同源，规避 iOS 26
//     自定义 scheme + HTML5 媒体兼容问题）；
//   - 挂载采用安全作用域书签（MountedFolderStore），原位访问、不复制文件；
//   - 视频用原生 AVPlayerViewController 播放，缩略图由原生 AVAssetImageGenerator 生成；
//   - 网页通过 WKScriptMessageHandler 桥接调用原生能力。
//

import UIKit
import WebKit
import UniformTypeIdentifiers
import AVKit
import AVFoundation

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

    var webView: WKWebView!
    var loadingView: UIActivityIndicatorView!

    /// 挂载配置页（弱引用，避免循环）
    private weak var mountConfigController: NativeMountViewController?
    /// 导入文件的"目标文件夹 id"（等待文件选择器返回）
    private var pendingImportFolderId: String?
    /// 当前原生播放器（保持强引用直到关闭）
    private var playerViewController: AVPlayerViewController?

    override func viewDidLoad() {
        super.viewDidLoad()

        LocalHTTPServer.shared.start()
        setupWebView()
        setupLoadingView()
        loadWebApp()
    }

    // MARK: - 设置 WKWebView

    private func setupWebView() {
        let config = WKWebViewConfiguration()

        // 注册原生桥接，网页通过 window.webkit.messageHandlers.nativeBridge.postMessage(...) 调用
        config.userContentController.add(self, name: "nativeBridge")

        config.allowsInlineMediaPlayback = true
        if #available(iOS 10.0, *) {
            config.mediaTypesRequiringUserActionForPlayback = []
        }
        if #available(iOS 14.0, *) {
            config.allowsPictureInPictureMediaPlayback = true
        }
        config.dataDetectorTypes = [.link, .phoneNumber]

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.backgroundColor = .white
        webView.scrollView.bounces = true
        webView.scrollView.alwaysBounceVertical = true
        webView.allowsBackForwardNavigationGestures = true

        view.addSubview(webView)
    }

    // MARK: - 设置加载指示器

    private func setupLoadingView() {
        loadingView = UIActivityIndicatorView(style: .large)
        loadingView.center = view.center
        loadingView.hidesWhenStopped = true
        loadingView.color = .systemBlue
        view.addSubview(loadingView)
    }

    // MARK: - 加载网页（本地 HTTP 服务）

    private func loadWebApp() {
        loadingView.startAnimating()
        let url = LocalHTTPServer.shared.baseURL.appendingPathComponent("index.html")
        webView.load(URLRequest(url: url))
    }

    // MARK: - 错误提示

    private func showError(message: String) {
        loadingView.stopAnimating()
        let alert = UIAlertController(title: "加载失败", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func showToast(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingView.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingView.stopAnimating()
        print("网页加载失败: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingView.stopAnimating()
        print("网页 provisional 加载失败: \(error.localizedDescription)")
    }

    // 允许所有导航
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    // MARK: - WKUIDelegate

    // 支持新窗口打开（target="_blank"）
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // 支持 JavaScript alert
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler()
        })
        present(alert, animated: true)
    }

    // 支持 JavaScript confirm
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            completionHandler(false)
        })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler(true)
        })
        present(alert, animated: true)
    }

    // MARK: - 屏幕方向 / 状态栏

    override var shouldAutorotate: Bool { return true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .all }
    override var prefersStatusBarHidden: Bool { return false }
    override var preferredStatusBarStyle: UIStatusBarStyle { return .default }

    // MARK: - 内存警告

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache],
                                                modifiedSince: Date(timeIntervalSince1970: 0),
                                                completionHandler: {})
    }
}

// MARK: - 原生桥接（网页 → 原生）

extension ViewController: WKScriptMessageHandler {

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "nativeBridge",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "mountFolder":
            presentMountConfig()
        case "importMedia":
            pendingImportFolderId = body["folderId"] as? String
            presentDocumentPicker(contentTypes: [.image, .movie], multiple: true)
        case "deleteFolder":
            deleteMountedFolder(body["folderId"] as? String)
        case "deleteMedia":
            deleteMountedFiles(body)
        case "playVideo":
            playVideo(folderId: body["folderId"] as? String, path: body["path"] as? String)
        case "makeThumbnail":
            makeVideoThumbnail(folderId: body["folderId"] as? String, path: body["path"] as? String)
        case "getServerInfo":
            // 注意：NSJSONSerialization 顶层必须是数组/字典，传字典而非裸字符串（否则抛 NSException 直接崩溃）
            let info: [String: Any] = ["base": LocalHTTPServer.shared.baseURL.absoluteString]
            evaluateJS("window.__nativeServerInfo(\(Self.jsonString(info)))")
        default:
            break
        }
    }

    /// 弹出"添加 本地"挂载配置页
    private func presentMountConfig() {
        guard mountConfigController == nil else { return }
        let vc = NativeMountViewController()
        vc.onMount = { [weak self] payload in
            guard let self = self else { return }
            self.evaluateJS("window.__nativeMountResult(\(Self.jsonString(payload)))")
        }
        vc.onError = { [weak self] message in
            guard let self = self else { return }
            self.evaluateJS("window.__nativeMountError(\(Self.jsonString(["message": message])))")
        }
        vc.onCancel = nil
        mountConfigController = vc
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }

    private func presentDocumentPicker(contentTypes: [UTType], multiple: Bool) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        picker.delegate = self
        picker.allowsMultipleSelection = multiple
        present(picker, animated: true)
    }

    /// 删除挂载：移除书签 + 清理旧版复制目录与导入目录（不动用户原文件夹）
    private func deleteMountedFolder(_ folderId: String?) {
        guard let folderId = folderId, !folderId.contains("..") else { return }
        let fm = FileManager.default
        MountedFolderStore.shared.remove(folderId: folderId)
        try? fm.removeItem(at: LocalHTTPServer.legacyMountedRoot.appendingPathComponent(folderId))
        try? fm.removeItem(at: LocalHTTPServer.importedRoot.appendingPathComponent(folderId))
    }

    /// 删除媒体文件：__imports__/ 前缀 = 导入文件；其余 = 旧版复制目录（书签挂载目录内的文件归用户所有，不删除）
    private func deleteMountedFiles(_ body: [String: Any]) {
        guard let folderId = body["folderId"] as? String, !folderId.contains(".."),
              let paths = body["paths"] as? [String] else { return }
        let fm = FileManager.default
        for raw in paths {
            let p = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !p.isEmpty, !p.contains("..") else { continue }
            if p.hasPrefix("__imports__/") {
                let rel = String(p.dropFirst("__imports__/".count))
                try? fm.removeItem(at: LocalHTTPServer.importedRoot.appendingPathComponent(folderId).appendingPathComponent(rel))
            } else {
                try? fm.removeItem(at: LocalHTTPServer.legacyMountedRoot.appendingPathComponent(folderId).appendingPathComponent(p))
            }
        }
    }

    // MARK: - 原生视频播放

    /// 用原生 AVPlayerViewController 播放（iOS 26 上比 HTML5 video + 自定义 scheme 可靠）
    private func playVideo(folderId: String?, path: String?) {
        guard let folderId = folderId, let path = path,
              let (url, cleanup) = LocalHTTPServer.resolveMediaFile(folderId: folderId, rel: Self.cleanPath(path)) else {
            showToast("找不到视频文件")
            return
        }
        let player = AVPlayer(url: url)
        let vc = NativePlayerViewController()
        vc.player = player
        vc.onDismiss = cleanup
        playerViewController = vc
        present(vc, animated: true) {
            player.play()
        }
    }

    // MARK: - 原生视频缩略图

    /// 原生生成视频第一帧缩略图，写入 Documents/thumbs，返回 HTTP URL 给网页
    private func makeVideoThumbnail(folderId: String?, path: String?) {
        guard let folderId = folderId, let path = path else { return }
        let folderIdC = folderId
        let pathC = path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let thumbURL = Self.generateVideoThumbnail(folderId: folderIdC, path: pathC)
            let payload: [String: Any] = ["folderId": folderIdC, "path": pathC, "url": thumbURL]
            self.evaluateJS("window.__nativeThumbnailResult(\(Self.jsonString(payload)))")
        }
    }

    private static func generateVideoThumbnail(folderId: String, path: String) -> String {
        guard let (url, cleanup) = LocalHTTPServer.resolveMediaFile(folderId: folderId, rel: cleanPath(path)) else {
            return ""
        }
        defer { cleanup() }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        let duration = asset.duration
        let seconds = duration.isValid && !duration.seconds.isNaN ? duration.seconds : 1.0
        let time = CMTime(seconds: min(1.0, max(0.0, seconds * 0.1)), preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return "" }
        let image = UIImage(cgImage: cgImage)
        guard let data = image.jpegData(compressionQuality: 0.7) else { return "" }

        let token = UUID().uuidString
        let fileURL = LocalHTTPServer.thumbsRoot.appendingPathComponent(token + ".jpg")
        do {
            try data.write(to: fileURL)
        } catch {
            return ""
        }
        return LocalHTTPServer.shared.baseURL
            .appendingPathComponent("thumbs")
            .appendingPathComponent(token + ".jpg")
            .absoluteString
    }

    // MARK: - 工具

    private func evaluateJS(_ script: String) {
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    private static func cleanPath(_ path: String) -> String {
        let cleaned = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return cleaned.contains("..") ? "" : cleaned
    }

    /// JSON 序列化（安全版）：NSJSONSerialization 对非法 JSON 对象抛 NSException，
    /// Swift try? 捕获不了，必须先 isValidJSONObject 校验，失败返回 "{}"。
    private static func jsonString(_ obj: Any) -> String {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
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

// MARK: - 原生播放器（关闭时释放安全作用域访问权）

final class NativePlayerViewController: AVPlayerViewController {
    var onDismiss: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onDismiss?()
        onDismiss = nil
    }
}

// MARK: - UIDocumentPicker 委托（导入文件用）

extension ViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        importFiles(urls)
    }

    /// 导入文件到指定文件夹：复制到 Documents/Imported/<folderId>/，路径前缀 __imports__/
    private func importFiles(_ urls: [URL]) {
        guard let folderId = pendingImportFolderId else { return }
        let destRoot = LocalHTTPServer.importedRoot.appendingPathComponent(folderId, isDirectory: true)
        let fm = FileManager.default
        var items: [[String: Any]] = []

        for url in urls {
            let filename = url.lastPathComponent
            guard Self.isMediaFile(filename) else { continue }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            var dest = destRoot.appendingPathComponent(filename)
            let base = (filename as NSString).deletingPathExtension
            let ext = (filename as NSString).pathExtension
            var counter = 1
            while fm.fileExists(atPath: dest.path) {
                dest = destRoot.appendingPathComponent("\(base)(\(counter)).\(ext)")
                counter += 1
            }
            guard let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber else { continue }
            do {
                try fm.copyItem(at: url, to: dest)
            } catch {
                continue
            }
            let savedName = dest.lastPathComponent
            items.append([
                "id": savedName,
                "name": filename,
                "path": "__imports__/\(savedName)",
                "type": Self.isVideoFile(filename) ? "video" : "image",
                "size": size.intValue
            ])
        }

        evaluateJS("window.__nativeImportResult(\(Self.jsonString(["items": items])))")
    }
}
