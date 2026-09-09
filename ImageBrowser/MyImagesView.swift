import SwiftUI
import PhotosUI
import UIKit

struct ImportedImage: Identifiable {
    let url: URL
    var id: String { url.lastPathComponent }
}

struct ViewerSelection: Identifiable {
    let id = UUID()
    let index: Int
}

/// “我的图片”页：从系统相册导入到 App 沙盒内浏览管理
struct MyImagesView: View {
    @State private var images: [ImportedImage] = []
    @State private var showPicker = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var viewerSelection: ViewerSelection?

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
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("还没有图片")
                            .font(.headline)
                        Text("点击右上角 + 从相册导入图片到本应用")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(Array(images.enumerated()), id: \.element.id) { index, item in
                                Button {
                                    viewerSelection = ViewerSelection(index: index)
                                } label: {
                                    LocalThumbnailCell(item: item)
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
                        showPicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("导入图片")
                }
            }
            .photosPicker(isPresented: $showPicker, selection: $pickerItems, maxSelectionCount: 20, matching: .images)
            .onChange(of: pickerItems) { newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await importItems(newItems)
                }
            }
            .task {
                reload()
            }
            .sheet(item: $viewerSelection) { selection in
                LocalImageViewer(images: images, startIndex: selection.index)
            }
        }
    }

    // MARK: - 导入

    private func importItems(_ items: [PhotosPickerItem]) async {
        let fm = FileManager.default
        try? fm.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let name = "IMG_\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(4)).jpg"
            let url = imagesDirectory.appendingPathComponent(name)
            do {
                try data.write(to: url)
            } catch {
                continue
            }
        }
        pickerItems = []
        reload()
    }

    // MARK: - 本地文件管理

    private func reload() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil) else {
            images = []
            return
        }
        let supported: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp", "tiff"]
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

/// 本地图片全屏翻页查看
struct LocalImageViewer: View {
    let images: [ImportedImage]
    @State private var index: Int
    @State private var showShare = false
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showShare) {
                if let image = UIImage(contentsOfFile: images[index].url.path) {
                    ActivityView(items: [image])
                }
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
