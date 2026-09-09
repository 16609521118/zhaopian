import SwiftUI
import UniformTypeIdentifiers
import UIKit
import PhotosUI

struct ImportedImage: Identifiable {
    let url: URL
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "3gp"]
    var isVideo: Bool { ImportedImage.videoExtensions.contains(url.pathExtension.lowercased()) }
    var id: String { url.lastPathComponent }
}

struct ViewerSelection: Identifiable {
    let id = UUID()
    let index: Int
}

struct PlaybackSelection: Identifiable {
    let id = UUID()
    let index: Int
}

/// “我的图片”页：从文件夹（系统文件选择器）或相册导入图片/视频到 App 沙盒内浏览管理
struct MyImagesView: View {
    @EnvironmentObject private var tabRouter: TabRouter
    @State private var images: [ImportedImage] = []
    @State private var viewerSelection: ViewerSelection?
    @State private var playbackSelection: PlaybackSelection?
    @State private var toast: String?
    @State private var photosPickerItems: [PhotosPickerItem] = []
    @State private var showFilePicker = false

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 4)
    ]

    private var imagesDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Images", isDirectory: true)
    }

    var body: some View {
        NavigationStack {
            Group {
                if images.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("还没有图片")
                            .font(.headline)
                        Text("导入方式：\n① 右上角 📷 从相册导入（已可用）\n② 右上角 📁 从文件夹选择，点文件后点「打开」\n③ 系统「文件」App → 我的 iPhone → 图览，\n   把图片放进来后点下方「刷新」")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            reload()
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 24)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(Array(images.enumerated()), id: \.element.id) { index, item in
                                Button {
                                    if item.isVideo {
                                        playbackSelection = PlaybackSelection(index: index)
                                    } else {
                                        viewerSelection = ViewerSelection(index: index)
                                    }
                                } label: {
                                    if item.isVideo {
                                        VideoGridCell(url: item.url)
                                    } else {
                                        LocalThumbnailCell(item: item)
                                    }
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        delete(item)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .navigationTitle("我的图片")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    PhotosPicker(
                        selection: $photosPickerItems,
                        maxSelectionCount: 20,
                        matching: .any(of: [.images, .videos])
                    ) {
                        Image(systemName: "photo.badge.plus")
                    }
                    .accessibilityLabel("从相册导入")

                    Button {
                        showFilePicker = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .accessibilityLabel("从文件夹导入")
                }
            }
            .sheet(isPresented: $showFilePicker) {
                UIKitDocumentPicker(
                    contentTypes: [.image, .movie],
                    allowsMultipleSelection: false
                ) { urls in
                    showFilePicker = false
                    importItems(urls)
                    tabRouter.selection = 1
                } onCancel: {
                    showFilePicker = false
                    showToast("未选择文件")
                }
            }
            .onChange(of: photosPickerItems) { items in
                guard !items.isEmpty else { return }
                let picked = items
                photosPickerItems = []
                Task { await importPhotos(picked) }
            }
            .task {
                reload()
            }
            .onReceive(NotificationCenter.default.publisher(for: .myImagesDidChange)) { _ in
                reload()
            }
            .overlay(alignment: .top) {
                if let toast {
                    ToastView(text: toast)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: toast)
            .sheet(item: $viewerSelection) { selection in
                LocalImageViewer(images: images, startIndex: selection.index)
            }
            .sheet(item: $playbackSelection) { selection in
                VideoPlayerSheet(url: images[selection.index].url)
            }
        }
    }

    // MARK: - 导入（从文件夹复制到沙盒）

    private func importItems(_ urls: [URL]) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        } catch {
            showToast("无法创建导入目录")
            return
        }
        var imported = 0
        var failed: [(String, String)] = []
        for url in urls {
            let opened = url.startAccessingSecurityScopedResource()
            defer {
                if opened { url.stopAccessingSecurityScopedResource() }
            }
            let base = url.lastPathComponent
            var name = base
            if fm.fileExists(atPath: imagesDirectory.appendingPathComponent(name).path) {
                name = "\(UUID().uuidString.prefix(8))_\(base)"
            }
            let dest = imagesDirectory.appendingPathComponent(name)
            do {
                try fm.copyItem(at: url, to: dest)
                imported += 1
            } catch let copyError {
                // 兜底：部分云盘 provider 返回虚拟路径，copyItem 失败时改用数据流读取
                do {
                    let data = try Data(contentsOf: url)
                    try data.write(to: dest)
                    imported += 1
                } catch {
                    failed.append((base, copyError.localizedDescription + " / " + error.localizedDescription))
                }
            }
        }
        reload()
        if imported > 0 {
            showToast("已导入 \(imported) 个文件")
        }
        if !failed.isEmpty {
            let detail = failed.prefix(2).map { "\($0.0)：\($0.1)" }.joined(separator: "；")
            showToast("导入失败：" + detail)
        }
    }

    // MARK: - 导入（从系统相册）

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        } catch {
            showToast("无法创建导入目录")
            return
        }
        var imported = 0
        var failed = 0
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                failed += 1
                continue
            }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let name = "\(UUID().uuidString.prefix(8)).\(ext)"
            do {
                try data.write(to: imagesDirectory.appendingPathComponent(name))
                imported += 1
            } catch {
                failed += 1
            }
        }
        reload()
        if imported > 0 {
            showToast("已导入 \(imported) 个文件")
        }
        if failed > 0 {
            showToast("\(failed) 个文件导入失败")
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                if toast == message { toast = nil }
            }
        }
    }

    // MARK: - 本地文件管理

    private func reload() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil) else {
            images = []
            return
        }
        let supported = ImportedImage.videoExtensions.union(
            ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp", "tiff"]
        )
        images = files
            .filter { supported.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { ImportedImage(url: $0) }
    }

    private func delete(_ item: ImportedImage) {
        try? FileManager.default.removeItem(at: item.url)
        reload()
    }
}

struct LocalThumbnailCell: View {
    let item: ImportedImage
    @State private var image: UIImage?

    var body: some View {
        Color(uiColor: .systemGray5)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .task(id: item.id) {
                if image == nil {
                    image = UIImage(contentsOfFile: item.url.path)
                }
            }
    }
}

/// 本地图片全屏翻页查看（详情 + 分享）
struct LocalImageViewer: View {
    let images: [ImportedImage]
    @State private var index: Int
    @State private var showShare = false
    @State private var showInfo = false
    @State private var fileInfo: LocalFileInfo?
    @Environment(\.dismiss) private var dismiss

    init(images: [ImportedImage], startIndex: Int) {
        self.images = images
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                TabView(selection: $index) {
                    ForEach(Array(images.enumerated()), id: \.element.id) { i, item in
                        LocalPage(url: item.url)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            }
            .navigationTitle("\(index + 1) / \(images.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("详情")

                    Button {
                        showShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("分享")
                }
            }
            .sheet(isPresented: $showShare) {
                if let image = UIImage(contentsOfFile: images[index].url.path) {
                    ActivityView(items: [image])
                }
            }
            .sheet(isPresented: $showInfo) {
                LocalFileInfoView(info: fileInfo)
            }
            .task(id: index) {
                fileInfo = await makeLocalFileInfo(url: images[index].url)
            }
        }
        .presentationDetents([.large])
    }
}

struct LocalPage: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                ZoomableImageView(image: image)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task(id: url.lastPathComponent) {
            if image == nil {
                image = UIImage(contentsOfFile: url.path)
            }
        }
    }
}
