import SwiftUI
import Photos
import UIKit
import AVFoundation
import CoreLocation
import ImageIO

/// 全屏查看页：左右滑动翻页，支持详情与分享
struct ImageDetailView: View {
    @EnvironmentObject private var vm: LibraryViewModel
    @State private var currentIndex: Int
    @State private var currentImage: UIImage?
    @State private var assetInfo: [String: String]?
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
            // 秒开：先展示同步可得的字段
            var info = Self.basicInfo(for: asset)
            assetInfo = info
            // 后台异步补齐：大小 / 拍摄设备 / 中文位置
            let extra = await Self.extraInfo(for: asset)
            info.merge(extra) { _, new in new }
            assetInfo = info
        }
    }

    /// 同步字段（打开详情立即显示，秒开）
    private static func basicInfo(for asset: PHAsset) -> [String: String] {
        var info: [String: String] = [:]
        let resources = PHAssetResource.assetResources(for: asset)
        info["文件名"] = resources.first?.originalFilename ?? "未知"
        info["类型"] = asset.mediaType == .video ? "视频" : "图片"
        info["尺寸"] = "\(asset.pixelWidth) × \(asset.pixelHeight) 像素"
        if asset.mediaType == .video {
            info["时长"] = Self.durationText(asset.duration)
        }
        if let date = asset.creationDate {
            info["拍摄时间"] = dateFormatter.string(from: date)
        }
        let collections = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
        if let album = collections.firstObject?.localizedTitle {
            info["所在相册"] = album
        }
        return info
    }

    /// 异步字段（后台加载，完成一项刷新一项）
    private static func extraInfo(for asset: PHAsset) async -> [String: String] {
        var extra: [String: String] = [:]
        extra["大小"] = await assetFileSizeText(for: asset)
        if let loc = asset.location {
            extra["拍摄位置"] = await PlaceNameResolver.shared.resolve(loc)
        }
        if let model = await cameraModel(for: asset) {
            extra["拍摄设备"] = model
        }
        return extra
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static func durationText(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%02d:%02d", m, sec)
    }

    /// 拍摄设备（Exif Make + Model，仅图片）
    private static func cameraModel(for asset: PHAsset) async -> String? {
        guard asset.mediaType == .image else { return nil }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .fastFormat
        let data = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        else {
            return nil
        }
        let make = tiff[kCGImagePropertyTIFFMake] as? String
        let model = tiff[kCGImagePropertyTIFFModel] as? String
        if let make, !make.isEmpty {
            if let model, !model.isEmpty {
                return "\(make) \(model)"
            }
            return make
        }
        return model
    }

    /// 通过 PHImageManager 请求资源数据以获取文件大小（PHAssetResource 不暴露大小）
    private static func assetFileSizeText(for asset: PHAsset) async -> String {
        if asset.mediaType == .video {
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            return await withCheckedContinuation { continuation in
                PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                    var bytes = 0
                    if let urlAsset = avAsset as? AVURLAsset {
                        let attrs = try? FileManager.default.attributesOfItem(atPath: urlAsset.url.path)
                        bytes = (attrs?[.size] as? NSNumber)?.intValue ?? 0
                    }
                    continuation.resume(returning: Self.sizeText(bytes))
                }
            }
        } else {
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            return await withCheckedContinuation { continuation in
                PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                    continuation.resume(returning: Self.sizeText(data?.count ?? 0))
                }
            }
        }
    }

    private static func sizeText(_ bytes: Int) -> String {
        bytes > 0 ? ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) : "—"
    }
}

/// 反地理编码（坐标 → 中文地名）结果缓存，避免重复请求网络
private actor PlaceNameResolver {
    static let shared = PlaceNameResolver()

    private var cache: [String: String] = [:]

    func resolve(_ loc: CLLocation) async -> String {
        let key = String(format: "%.4f,%.4f", loc.coordinate.latitude, loc.coordinate.longitude)
        if let hit = cache[key] {
            return hit
        }
        var name = String(format: "%.6f, %.6f", loc.coordinate.latitude, loc.coordinate.longitude)
        let geocoder = CLGeocoder()
        let places = try? await geocoder.reverseGeocodeLocation(loc)
        if let place = places?.first {
            let parts = [place.administrativeArea, place.locality, place.subLocality, place.name]
                .compactMap { $0 }
            if !parts.isEmpty {
                name = parts.joined(separator: " ")
            } else if let country = place.country {
                name = country
            }
        }
        cache[key] = name
        return name
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
