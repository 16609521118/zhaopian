//
//  ViewerViewController.swift
//  PhotoViewer
//
//  全屏查看器：UIPageViewController 左右滑动切换媒体。
//  图片：UIScrollView 双指缩放 / 双击缩放；视频：AVPlayerViewController 原生播放。
//

import UIKit
import AVKit
import AVFoundation

// MARK: - 主查看器

final class ViewerViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    private let folder: MountedFolder
    private let items: [MediaItem]
    private var currentIndex: Int
    private let pageVC: UIPageViewController

    private let topBar = UIView()
    private let closeButton = UIButton(type: .system)
    private let counterLabel = UILabel()
    private let nameLabel = UILabel()

    init(folder: MountedFolder, items: [MediaItem], startIndex: Int) {
        self.folder = folder
        self.items = items
        self.currentIndex = startIndex
        self.pageVC = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        pageVC.dataSource = self
        pageVC.delegate = self
        pageVC.setViewControllers([makePage(index: currentIndex)], direction: .forward, animated: false)

        addChild(pageVC)
        pageVC.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageVC.view)
        pageVC.didMove(toParent: self)

        setupTopBar()
        updateLabels()
    }

    private func setupTopBar() {
        topBar.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(closeButton)

        counterLabel.textColor = .white
        counterLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        counterLabel.textAlignment = .center
        counterLabel.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(counterLabel)

        nameLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            pageVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 52),

            closeButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 8),
            closeButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            counterLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            counterLabel.topAnchor.constraint(equalTo: topBar.topAnchor, constant: 6),

            nameLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            nameLabel.topAnchor.constraint(equalTo: counterLabel.bottomAnchor, constant: 2),
            nameLabel.leadingAnchor.constraint(greaterThanOrEqualTo: topBar.leadingAnchor, constant: 56),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: topBar.trailingAnchor, constant: -56)
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func updateLabels() {
        counterLabel.text = "\(currentIndex + 1) / \(items.count)"
        nameLabel.text = items[currentIndex].name
    }

    private func makePage(index: Int) -> UIViewController {
        let item = items[index]
        if item.type == .video {
            return VideoPageViewController(item: item, folder: folder, index: index)
        }
        return ImagePageViewController(item: item, folder: folder, index: index)
    }

    // MARK: - UIPageViewController

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? PageIndexProviding, page.pageIndex > 0 else { return nil }
        return makePage(index: page.pageIndex - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? PageIndexProviding, page.pageIndex < items.count - 1 else { return nil }
        return makePage(index: page.pageIndex + 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController],
                            transitionCompleted completed: Bool) {
        guard completed, let page = pageViewController.viewControllers?.first as? PageIndexProviding else { return }
        currentIndex = page.pageIndex
        updateLabels()
    }
}

protocol PageIndexProviding: AnyObject {
    var pageIndex: Int { get }
}

// MARK: - 图片页（缩放）

final class ImagePageViewController: UIViewController, PageIndexProviding, UIScrollViewDelegate {

    let pageIndex: Int
    private let item: MediaItem
    private let folder: MountedFolder
    private let store = FolderStore.shared
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private var accessedURL: URL?

    init(item: MediaItem, folder: MountedFolder, index: Int) {
        self.item = item
        self.folder = folder
        self.pageIndex = index
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    deinit {
        accessedURL?.stopAccessingSecurityScopedResource()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
            imageView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        loadImage()
    }

    private func loadImage() {
        guard let url = store.fileURL(for: item, in: folder) else { return }
        accessedURL = url
        let accessing = url.startAccessingSecurityScopedResource()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // 全屏查看用屏幕尺寸降采样（兼顾清晰度与内存）
            let maxDim = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * UIScreen.main.scale
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            var image: UIImage?
            if let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) {
                let options = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxDim
                ] as CFDictionary
                if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
                    image = UIImage(cgImage: cgImage)
                }
            }
            // 图片已读入内存，释放文件访问
            if accessing { url.stopAccessingSecurityScopedResource() }
            DispatchQueue.main.async {
                self?.imageView.image = image
            }
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1.01 {
            scrollView.setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let rect = CGRect(x: point.x - 80, y: point.y - 80, width: 160, height: 160)
            scrollView.zoom(to: rect, animated: true)
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
}

// MARK: - 视频页（原生 AVPlayer）

final class VideoPageViewController: UIViewController, PageIndexProviding {

    let pageIndex: Int
    private let item: MediaItem
    private let folder: MountedFolder
    private let store = FolderStore.shared
    private let playerVC = AVPlayerViewController()
    private var accessedURL: URL?

    init(item: MediaItem, folder: MountedFolder, index: Int) {
        self.item = item
        self.folder = folder
        self.pageIndex = index
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    deinit {
        accessedURL?.stopAccessingSecurityScopedResource()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        addChild(playerVC)
        playerVC.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playerVC.view)
        playerVC.didMove(toParent: self)

        NSLayoutConstraint.activate([
            playerVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            playerVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        if let url = store.fileURL(for: item, in: folder) {
            accessedURL = url
            url.startAccessingSecurityScopedResource()
            playerVC.player = AVPlayer(url: url)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        playerVC.player?.pause()
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }
}
