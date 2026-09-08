//
//  ViewController.swift
//  PhotoViewer
//
//  极简版：启动本地 HTTP 服务 → WKWebView 加载 http://127.0.0.1:<port>/
//  所有数据（文件夹列表、媒体文件）都通过 HTTP 接口获取，不依赖
//  UIDocumentPickerViewController（iOS 26 文件夹选择器有系统缺陷）。
//

import UIKit
import WebKit

final class ViewController: UIViewController {

    private var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // 启动本地 HTTP 服务（仅 127.0.0.1）
        LocalHTTPServer.shared.start()

        setupWebView()
        loadApp()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.scrollView.bounces = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        self.webView = webView
    }

    private func loadApp() {
        let url = LocalHTTPServer.shared.baseURL
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(request)
    }
}
