import SwiftUI
import UIKit
import AVFoundation
import AVKit
import ImageIO

/// 相册权限被拒绝时的引导视图
struct PermissionView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("需要访问相册权限")
                .font(.headline)
            Text("请在系统设置中允许本应用访问您的照片，才能浏览相册。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - 本地文件信息（详情）

struct LocalFileInfo: Identifiable {
    let id = UUID()
    let name: String
    let kindText: String
    let sizeText: String
    let modifiedText: String
}

/// 生成本地文件（图片/视频）详情信息
func makeLocalFileInfo(url: URL) -> LocalFileInfo {
    let fm = FileManager.default
    let attrs = try? fm.attributesOfItem(atPath: url.path)
    let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    let sizeText = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    let date = attrs?[.modificationDate] as? Date
    let dateText = date.map { LocalFileInfoDateFormatter.string(from: $0) } ?? "—"
    let ext = url.pathExtension.lowercased()

    if ImportedImage.videoExtensions.contains(ext) {
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        let durationText = seconds.isFinite ? formattedDuration(seconds) : "—"
        return LocalFileInfo(
            name: url.lastPathComponent,
            kindText: "视频 · \(durationText)",
            sizeText: sizeText,
            modifiedText: dateText
        )
    }

    if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
       let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
       let w = props[kCGImagePropertyPixelWidth] as? Int,
       let h = props[kCGImagePropertyPixelHeight] as? Int {
        return LocalFileInfo(
            name: url.lastPathComponent,
            kindText: "图片 · \(w) × \(h)",
            sizeText: sizeText,
            modifiedText: dateText
        )
    }
    return LocalFileInfo(
        name: url.lastPathComponent,
        kindText: "文件",
        sizeText: sizeText,
        modifiedText: dateText
    )
}

private let LocalFileInfoDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f
}()

private func formattedDuration(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    return String(format: "%02d:%02d", s / 60, s % 60)
}

struct LocalFileInfoView: View {
    let info: LocalFileInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                LabeledContent("名称", value: info.name)
                LabeledContent("类型", value: info.kindText)
                LabeledContent("大小", value: info.sizeText)
                LabeledContent("修改时间", value: info.modifiedText)
            }
            .navigationTitle("详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 相册资产详情（PHAsset）
struct AssetInfoView: View {
    let info: [String: String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(info.keys.sorted(), id: \.self) { key in
                    LabeledContent(key, value: info[key] ?? "—")
                }
            }
            .navigationTitle("详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 视频支持

/// 视频缩略图：AVAssetImageGenerator 取首帧附近画面
enum VideoThumbnailLoader {
    static func thumbnail(url: URL, maxPixel: CGFloat = 240) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        let time = CMTime(seconds: 1, preferredTimescale: 600)
        do {
            let cg = try generator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cg)
        } catch {
            guard let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
            return UIImage(cgImage: cg)
        }
    }
}

/// 视频网格单元（缩略图 + 播放角标）
struct VideoGridCell: View {
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
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .shadow(radius: 1)
                    .padding(4)
            }
            .clipped()
            .task(id: url.path) {
                if image == nil {
                    image = await Task.detached(priority: .utility) {
                        VideoThumbnailLoader.thumbnail(url: url)
                    }.value
                }
            }
    }
}

/// 视频播放页（AVPlayer）
struct VideoPlayerSheet: View {
    let url: URL
    @State private var player: AVPlayer?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .navigationTitle("视频")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                if player == nil {
                    player = AVPlayer(url: url)
                }
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
        }
        .presentationDetents([.large])
    }
}
