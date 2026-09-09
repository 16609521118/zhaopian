import SwiftUI
import UniformTypeIdentifiers
import UIKit

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

/// “我的图片”页：从文件夹（文件选择器）导入图片/视频到 App 沙盒内浏览管理
struct MyImagesView: View {
    @State private var images: [ImportedImage] = []
    @State private var showImporter = false
    @State private var viewerSelection: ViewerSelection?
    @State private var playbackSelection: PlaybackSelection?

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
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("还没有图片")
                            .font(.headline)
                        Text("点击右上角从文件夹导入图片或视频\n文件会复制保存到本应用内")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .accessibilityLabel("从文件夹导入")
                }
            }
            .sheet(isPresented: $showImporter) {
                DocumentPicker(
                    contentTypes: [.image, .movie],
                    allowsMultipleSelection: true
                ) { urls in
                    Task { await importItems(urls) }
                }
            }
            .task {
                reload()
            }
            .sheet(item: $viewerSelection) { selection in
                LocalImageViewer(images: images, startIndex: selection.index)
            }
            .sheet(item: $playbackSelection) { selection in
                VideoPlayerSheet(url: images[selection.index].url)
            }
        }
    }

    // MARK: - 导入（从文件夹复制到沙盒）

    private func importItems(_ urls: [URL]) async {
        let fm = FileManager.default
        try? fm.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        for url in urls {
            let opened = url.startAccessingSecurityScopedResource()
            defer {
                if opened {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let base = url.lastPathComponent
            var name = base
            if fm.fileExists(atPath: imagesDirectory.appendingPathComponent(name).path) {
                name = "\(UUID().uuidString.prefix(8))_\(base)"
            }
            do {
                try fm.copyItem(at: url, to: imagesDirectory.appendingPathComponent(name))
            } catch {
                continue
            }
        }
        reload()
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
