//
//  ViewController.swift
//  PhotoViewer
//
//  iOS 图片/视频查看器 - 主视图控制器（WKWebView 加载本地网页）
//  通过 WKScriptMessageHandler 桥接网页与原生：挂载文件夹、导入文件、删除文件均由原生
//  UIDocumentPicker 完成，文件复制到 App 沙盒后经 localapp:// scheme 离线访问。
//

import UIKit
import WebKit
import UniformTypeIdentifiers

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

    var webView: WKWebView!
    var loadingView: UIActivityIndicatorView!

    private var schemeHandler = LocalFileSchemeHandler()
    private var pendingImportFolderId: String?

    // MARK: - 挂载配置页（弱引用，避免循环）
    private weak var mountConfigController: NativeMountViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupWebView()
        setupLoadingView()
        loadLocalWebApp()
    }

    // MARK: - 设置 WKWebView
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        
        // 注册自定义 scheme，网页用 localapp://media/... 访问沙盒文件（完全离线）
        config.setURLSchemeHandler(schemeHandler, forURLScheme: LocalFileSchemeHandler.scheme)

        // 注册原生桥接，网页通过 window.webkit.messageHandlers.nativeBridge.postMessage(...) 调用
        config.userContentController.add(self, name: "nativeBridge")

        // 允许从 file:// 页面加载相对资源（icons、manifest 等）
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        // 允许视频自动播放（不静音）
        config.allowsInlineMediaPlayback = true
        if #available(iOS 10.0, *) {
            config.mediaTypesRequiringUserActionForPlayback = []
        }
        
        // 启用视频画中画
        if #available(iOS 14.0, *) {
            config.allowsPictureInPictureMediaPlayback = true
        }
        
        // 数据检测器
        config.dataDetectorTypes = [.link, .phoneNumber]
        
        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.backgroundColor = .white
        webView.scrollView.bounces = true
        webView.scrollView.alwaysBounceVertical = true
        
        // 允许侧滑返回（如果有导航的话）
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

    // MARK: - 加载本地网页应用
    private func loadLocalWebApp() {
        loadingView.startAnimating()
        
        // 兼容两种打包位置：Xcode 默认把资源扁平拷贝到 App 包根目录，
        // 某些配置下会保留在 web/ 子目录，这里自动查找并优先 web/ 子目录
        guard let htmlURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web")
            ?? Bundle.main.url(forResource: "index", withExtension: "html") else {
            showError(message: "找不到网页资源文件")
            return
        }
        
        do {
            let htmlString = try String(contentsOf: htmlURL, encoding: .utf8)
            let baseURL = htmlURL.deletingLastPathComponent()
            webView.loadHTMLString(htmlString, baseURL: baseURL)
        } catch {
            showError(message: "读取网页文件失败: \(error.localizedDescription)")
        }
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

    // 允许加载本地文件和所有 URL
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

    // MARK: - 屏幕方向
    override var shouldAutorotate: Bool {
        return true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }

    // MARK: - 状态栏
    override var prefersStatusBarHidden: Bool {
        return false
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }

    // MARK: - 内存警告
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // 清理缓存
        WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache], modifiedSince: Date(timeIntervalSince1970: 0), completionHandler: {})
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
            deleteMountedFiles(body["paths"] as? [String])
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

    private func deleteMountedFolder(_ folderId: String?) {
        guard let folderId = folderId, !folderId.contains("..") else { return }
        try? FileManager.default.removeItem(at: LocalFileSchemeHandler.mountedRoot.appendingPathComponent(folderId))
    }

    private func deleteMountedFiles(_ paths: [String]?) {
        guard let paths = paths else { return }
        for p in paths where !p.contains("..") {
            try? FileManager.default.removeItem(at: LocalFileSchemeHandler.mountedRoot.appendingPathComponent(p))
        }
    }
}

// MARK: - UIDocumentPicker 委托（导入文件用）
extension ViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        importFiles(urls)
    }

    // MARK: 导入文件到已有文件夹

    private func importFiles(_ urls: [URL]) {
        guard let folderId = pendingImportFolderId else { return }
        let destRoot = LocalFileSchemeHandler.mountedRoot.appendingPathComponent(folderId, isDirectory: true)
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
            let rel = dest.lastPathComponent
            items.append([
                "id": rel,
                "name": filename,
                "url": "localapp://media/\(folderId)/\(Self.encodePath(rel))",
                "type": Self.isVideoFile(filename) ? "video" : "image",
                "size": size.intValue
            ])
        }

        evaluateJS("window.__nativeImportResult(\(Self.jsonString(["items": items])))")
    }

    // MARK: 工具

    private func evaluateJS(_ script: String) {
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(script, completionHandler: nil)
        }
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

    private static func jsonString(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
