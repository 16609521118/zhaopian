import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ImageIO

/// 单个目录项：文件夹、图片或视频
struct FolderItem: Identifiable {
    let url: URL
    let isDirectory: Bool
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "3gp"]
    var isVideo: Bool { !isDirectory && FolderItem.videoExtensions.contains(url.pathExtension.lowercased()) }
    var id: String { url.path }
}

/// “文件夹”页：挂载管理 + 目录浏览（正规的本地文件夹映射，非复制）
struct MountedFoldersView: View {
    @EnvironmentObject private var vm: FolderViewModel
    @EnvironmentObject private var tabRouter: TabRouter
    @State private var toast: String?
    @State private var showFolderImporter = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.folders.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "externaldrive.badge.plus")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("还没有挂载文件夹")
                            .font(.headline)
                        Text("方式一（推荐，不弹选择器）：\n系统「文件」App → 我的 iPhone → 图览\n把整个文件夹放进来，回到本页即可浏览\n\n方式二：\n点右上角 + ，浏览页选中文件夹后点「打开」\n（挂载后文件不会复制，直接读取原位置）")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    List {
                        Section {
                            NavigationLink(value: "local-server") {
                                Label("局域网映射（IP 访问）", systemImage: "network")
                            }
                        } header: {
                            Text("映射方式")
                        } footer: {
                            Text("App 内启动局域网服务，电脑浏览器访问地址即可向“我的图片”上传 / 下载文件")
                        }

                        Section("已挂载文件夹") {
                            ForEach(vm.folders) { folder in
                                NavigationLink(value: FolderBrowserView.FolderRoot(url: folder.url, displayName: folder.displayName, isScoped: true)) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "folder.fill")
                                            .font(.title2)
                                            .foregroundStyle(.tint)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(folder.displayName)
                                                .foregroundStyle(.primary)
                                            Text(folder.url.path)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        vm.unmount(folder)
                                    } label: {
                                        Label("卸载", systemImage: "eject")
                                    }
                                }
                            }
                        }

                        Section("App 内文件夹（从「文件」App 放入）") {
                            if sandboxFolders.isEmpty {
                                Text("用系统「文件」App 把整个文件夹放进\n「我的 iPhone → 图览」，回到本页即可浏览")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(sandboxFolders, id: \.path) { url in
                                    NavigationLink(value: FolderBrowserView.FolderRoot(url: url, displayName: url.lastPathComponent, isScoped: false)) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "folder.fill")
                                                .font(.title2)
                                                .foregroundStyle(.tint)
                                            Text(url.lastPathComponent)
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("文件夹")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showFolderImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("挂载文件夹")
                }
            }
            .fileImporter(
                isPresented: $showFolderImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        if let err = vm.mount(url: url) {
                            showToast("挂载失败：\(err)")
                        } else {
                            showToast("已挂载 1 个文件夹")
                        }
                    } else {
                        showToast("未选择文件夹")
                    }
                case .failure:
                    showToast("未选择文件夹")
                }
                tabRouter.selection = 2
            }
            .overlay(alignment: .top) {
                if let toast {
                    ToastView(text: toast)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: toast)
            .navigationDestination(for: FolderBrowserView.FolderRoot.self) { root in
                FolderBrowserView(root: root)
            }
            .navigationDestination(for: String.self) { value in
                if value == "local-server" {
                    LocalServerView()
                }
            }
        }
    }

    /// Documents 沙盒内的文件夹（用户通过系统「文件」App 放入）
    private var sandboxFolders: [URL] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return items.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
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
}

/// 文件夹浏览：支持进入子目录、返回上级，图片/视频网格 + 全屏查看
struct FolderBrowserView: View {
    /// 浏览根目录：挂载的文件夹（isScoped = 需要安全作用域）或 App 沙盒内目录
    struct FolderRoot: Hashable, Identifiable {
        let url: URL
        let displayName: String
        let isScoped: Bool
        var id: String { url.path }
    }

    let root: FolderRoot
    @State private var path: [URL] = []
    @State private var items: [FolderItem] = []
    @State private var viewerSelection: ViewerSelection?
    @State private var playbackSelection: PlaybackSelection?

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 4)
    ]

    private var currentURL: URL { path.last ?? root.url }

    private var currentImageList: [ImportedImage] {
        items
            .filter { !$0.isDirectory && !$0.isVideo }
            .map { ImportedImage(url: $0.url) }
    }

    private var currentVideoList: [FolderItem] {
        items.filter { $0.isVideo }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("此文件夹为空")
                        .foregroundStyle(.secondary)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(items) { item in
                            if item.isDirectory {
                                Button {
                                    path.append(item.url)
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 36))
                                            .foregroundStyle(.tint)
                                        Text(item.url.lastPathComponent)
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                                }
                                .buttonStyle(.plain)
                            } else if item.isVideo {
                                Button {
                                    if let idx = videoIndex(for: item) {
                                        playbackSelection = PlaybackSelection(index: idx)
                                    }
                                } label: {
                                    VideoGridCell(url: item.url)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    if let idx = imageIndex(for: item) {
                                        viewerSelection = ViewerSelection(index: idx)
                                    }
                                } label: {
                                    FolderThumbnailCell(url: item.url)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(4)
                }
            }
        }
        .navigationTitle(path.isEmpty ? root.displayName : currentURL.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !path.isEmpty {
                    Button {
                        path.removeLast()
                    } label: {
                        Label("上级", systemImage: "chevron.left")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    scan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新")
            }
        }
        .task(id: path) {
            scan()
        }
        .onAppear {
            if root.isScoped {
                _ = root.url.startAccessingSecurityScopedResource()
            }
        }
        .onDisappear {
            if root.isScoped {
                root.url.stopAccessingSecurityScopedResource()
            }
        }
        .sheet(item: $viewerSelection) { selection in
            LocalImageViewer(images: currentImageList, startIndex: selection.index)
        }
        .sheet(item: $playbackSelection) { selection in
            VideoPlayerSheet(url: currentVideoList[selection.index].url)
        }
    }

    // MARK: - 扫描

    private func scan() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: currentURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            items = []
            return
        }
        let supported = FolderItem.videoExtensions.union(
            ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp", "tiff"]
        )
        var dirs: [FolderItem] = []
        var imgs: [FolderItem] = []
        for u in urls {
            let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                dirs.append(FolderItem(url: u, isDirectory: true))
            } else if supported.contains(u.pathExtension.lowercased()) {
                imgs.append(FolderItem(url: u, isDirectory: false))
            }
        }
        dirs.sort { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
        imgs.sort { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
        items = dirs + imgs
    }

    private func imageIndex(for item: FolderItem) -> Int? {
        currentImageList.firstIndex { $0.url == item.url }
    }

    private func videoIndex(for item: FolderItem) -> Int? {
        currentVideoList.firstIndex { $0.url == item.url }
    }
}

/// 文件夹内图片缩略图（ImageIO 直读缩略图，不解码原图，快且省内存）
struct FolderThumbnailCell: View {
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
                    image = await Task.detached(priority: .utility) {
                        ImageThumbnailLoader.thumbnail(url: url, maxPixel: 240)
                    }.value
                }
            }
    }
}

/// 非 MainActor 隔离的 ImageIO 缩略图加载器
enum ImageThumbnailLoader {
    static func thumbnail(url: URL, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
