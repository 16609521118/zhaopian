import SwiftUI
import Photos
import UIKit

/// 相册网格页
struct LibraryView: View {
    @EnvironmentObject private var vm: LibraryViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if !vm.isAuthorized {
                    PermissionView()
                } else if vm.assets.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text(vm.isLoading ? "正在加载…" : "相册里没有图片")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(Array(vm.assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                                NavigationLink(value: index) {
                                    ThumbnailCell(asset: asset)
                                        .id(asset.localIdentifier)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle(vm.albumTitle)
            .navigationDestination(for: Int.self) { index in
                ImageDetailView(startIndex: index)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if vm.albumTitle != "全部照片" {
                        Button("全部") {
                            vm.setAlbum(nil)
                        }
                    }
                    Button {
                        vm.refreshAuthorization()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新")
                }
            }
        }
    }
}

/// 单个缩略图
struct ThumbnailCell: View {
    let asset: PHAsset
    @EnvironmentObject private var vm: LibraryViewModel
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
            .task(id: asset.localIdentifier) {
                if image == nil {
                    image = await vm.requestThumbnail(for: asset, targetSize: CGSize(width: 240, height: 240))
                }
            }
    }
}
