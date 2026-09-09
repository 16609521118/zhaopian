import SwiftUI
import UIKit

struct ViewerSelection: Identifiable {
    let id = UUID()
    let index: Int
}

/// 挂载文件夹内容浏览：子文件夹 + 图片 + 视频（支持进入子文件夹）
struct FolderBrowserView: View {
    let root: URL
    @State private var title = ""
    @State private var entries: [URL] = []
    @State private var images: [URL] = []
    @State private var viewerSelection: ViewerSelection?
    @State private var playbackSelection: ViewerSelection?

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 4)]
    private let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp", "tiff"]
    private let videoExts: Set<String> = ["mp4", "mov", "m4v", "3gp"]

    var body: some View {
        Group {
            if entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("文件夹为空")
                        .font(.headline)
                    Button("刷新") { reload() }
                        .buttonStyle(.bordered)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(Array(entries.enumerated()), id: \.element) { _, url in
                            if url.hasDirectoryPath {
                                NavigationLink(value: url) {
                                    FolderCell(url: url)
                                }
                                .buttonStyle(.plain)
                            } else if videoExts.contains(url.pathExtension.lowercased()) {
                                Button {
                                    if let i = images.firstIndex(of: url) {
                                        playbackSelection = ViewerSelection(index: i)
                                    }
                                } label: {
                                    VideoGridCell(url: url)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    if let i = images.firstIndex(of: url) {
                                        viewerSelection = ViewerSelection(index: i)
                                    }
                                } label: {
                                    LocalThumbnailCell(url: url)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        delete(url)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(4)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: URL.self) { url in
            FolderBrowserView(root: url)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新")
            }
        }
        .sheet(item: $viewerSelection) { selection in
            LocalImageViewer(urls: images, startIndex: selection.index)
        }
        .sheet(item: $playbackSelection) { selection in
            VideoPlayerSheet(url: images[selection.index])
        }
        .task {
            title = root.lastPathComponent
            reload()
        }
    }

    private func reload() {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let sorted = items.sorted { $0.lastPathComponent < $1.lastPathComponent }
        entries = sorted
        images = sorted.filter {
            imageExts.contains($0.pathExtension.lowercased()) || videoExts.contains($0.pathExtension.lowercased())
        }
    }

    private func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        reload()
    }
}

/// 子文件夹网格单元
struct FolderCell: View {
    let url: URL

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text(url.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// 图片网格缩略图
struct LocalThumbnailCell: View {
    let url: URL
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
            .task(id: url.path) {
                if image == nil {
                    image = UIImage(contentsOfFile: url.path)
                }
            }
    }
}

/// 图片全屏翻页查看（详情 + 分享）
struct LocalImageViewer: View {
    let urls: [URL]
    @State private var index: Int
    @State private var showShare = false
    @State private var showInfo = false
    @State private var fileInfo: LocalFileInfo?
    @Environment(\.dismiss) private var dismiss

    init(urls: [URL], startIndex: Int) {
        self.urls = urls
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                TabView(selection: $index) {
                    ForEach(Array(urls.enumerated()), id: \.element) { i, url in
                        LocalPage(url: url)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            }
            .navigationTitle("\(index + 1) / \(urls.count)")
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
                if let image = UIImage(contentsOfFile: urls[index].path) {
                    ActivityView(items: [image])
                }
            }
            .sheet(isPresented: $showInfo) {
                LocalFileInfoView(info: fileInfo)
            }
            .task(id: index) {
                fileInfo = await makeLocalFileInfo(url: urls[index])
            }
        }
        .presentationDetents([.large])
    }
}

/// 全屏单页（支持缩放）
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
