import SwiftUI
import Photos
import UIKit

/// 全屏查看页：左右滑动翻页，支持详情与分享
struct ImageDetailView: View {
    @EnvironmentObject private var vm: LibraryViewModel
    @State private var currentIndex: Int
    @State private var currentImage: UIImage?
    @State private var assetInfo: [String: String] = [:]
    @State private var showShare = false
    @State private var showInfo = false

    init(startIndex: Int) {
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(vm.assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                    FullImageView(asset: asset)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack {
                Spacer()
                HStack(spacing: 24) {
                    Text("\(currentIndex + 1) / \(vm.assets.count)")
                        .font(.footnote.monospacedDigit())
                    Spacer()
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .disabled(currentImage == nil)
                    .accessibilityLabel("详情")

                    Button {
                        showShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(currentImage == nil)
                    .accessibilityLabel("分享")
                }
                .font(.title3)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(.bottom, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showShare) {
            if let currentImage {
                ActivityView(items: [currentImage])
            }
        }
        .sheet(isPresented: $showInfo) {
            AssetInfoView(info: assetInfo)
        }
        .task(id: currentIndex) {
            guard vm.assets.indices.contains(currentIndex) else { return }
            let asset = vm.assets[currentIndex]
            currentImage = await vm.requestFullImage(for: asset)
            assetInfo = Self.info(for: asset)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static func info(for asset: PHAsset) -> [String: String] {
        var info: [String: String] = [:]
        let resources = PHAssetResource.assetResources(for: asset)
        info["文件名"] = resources.first?.originalFilename ?? "未知"
        if let date = asset.creationDate {
            info["拍摄时间"] = dateFormatter.string(from: date)
        }
        info["尺寸"] = "\(asset.pixelWidth) × \(asset.pixelHeight)"
        let size = resources.first?.fileSize ?? 0
        info["大小"] = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        info["类型"] = asset.mediaType == .video ? "视频" : "图片"
        return info
    }
}

/// 单页全屏图片（按需加载原图）
struct FullImageView: View {
    let asset: PHAsset
    @EnvironmentObject private var vm: LibraryViewModel
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
        .task(id: asset.localIdentifier) {
            if image == nil {
                image = await vm.requestFullImage(for: asset)
            }
        }
    }
}
