//
//  ViewController.swift
//  PhotoViewer
//
//  iOS 图片/视频查看器 - 主视图控制器（WKWebView 加载本地网页）
//

import UIKit
import WebKit

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

    var webView: WKWebView!
    var loadingView: UIActivityIndicatorView!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupWebView()
        setupLoadingView()
        loadLocalWebApp()
    }

    // MARK: - 设置 WKWebView
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        
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
