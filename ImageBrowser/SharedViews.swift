import SwiftUI
import UIKit
import AVFoundation
import AVKit
import ImageIO

// MARK: - 顶部轻提示

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.75), in: Capsule())
            .foregroundStyle(.white)
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

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

struct InfoRow: Identifiable {
    let id = UUID()
    let key: String
    let value: String
}

struct LocalFileInfo: Identifiable {
    let id = UUID()
    let rows: [InfoRow]
}

/// 生成本地文件（图片/视频）超详细详情信息
func makeLocalFileInfo(url: URL) async -> LocalFileInfo {
    let fm = FileManager.default
    var rows: [InfoRow] = []
    rows.append(InfoRow(key: "名称", value: url.lastPathComponent))

    let attrs = try? fm.attributesOfItem(atPath: url.path)
    let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    let sizeText = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    let created = attrs?[.creationDate] as? Date
    let modified = attrs?[.modificationDate] as? Date
    let ext = url.pathExtension.uppercased()
    rows.append(InfoRow(key: "格式", value: ext.isEmpty ? "未知" : ext))

    let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "3gp"]
    if videoExtensions.contains(url.pathExtension.lowercased()) {
        let asset = AVURLAsset(url: url)
        var seconds = 0.0
        if let duration = try? await asset.load(.duration) {
            seconds = CMTimeGetSeconds(duration)
        }
        let durationText = seconds.isFinite ? formattedDuration(seconds) : "—"
        rows.append(InfoRow(key: "类型", value: "视频"))
        rows.append(InfoRow(key: "时长", value: durationText))
    } else {
        rows.append(InfoRow(key: "类型", value: "图片"))
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
            let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
            if w > 0 && h > 0 {
                rows.append(InfoRow(key: "尺寸", value: "\(w) × \(h) 像素（约 " + String(format: "%.1f", Double(w * h) / 1_000_000.0) + " MP）"))
                rows.append(InfoRow(key: "宽高比", value: String(format: "%.3f", Double(w) / Double(h))))
            }
            let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
            let make = tiff?[kCGImagePropertyTIFFMake] as? String
            let model = tiff?[kCGImagePropertyTIFFModel] as? String
            if let make, !make.isEmpty, let model, !model.isEmpty {
                rows.append(InfoRow(key: "设备型号", value: "\(make) \(model)"))
            } else if let model, !model.isEmpty {
                rows.append(InfoRow(key: "设备型号", value: model))
            }
            if let fnumber = exif?[kCGImagePropertyExifFNumber] as? NSNumber {
                rows.append(InfoRow(key: "光圈", value: "f/" + String(format: "%.1f", fnumber.doubleValue)))
            }
            if let expo = exif?[kCGImagePropertyExifExposureTime] as? NSNumber {
                let t = expo.doubleValue
                if t > 0 {
                    rows.append(InfoRow(key: "快门", value: t >= 1 ? String(format: "1/%.0f 秒", 1.0 / t) : String(format: "%.1f 秒", t)))
                }
            }
            if let isoList = exif?[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber], let iso = isoList.first {
                rows.append(InfoRow(key: "ISO", value: "\(iso.intValue)"))
            }
            if let focal = exif?[kCGImagePropertyExifFocalLength] as? NSNumber {
                rows.append(InfoRow(key: "焦距", value: String(format: "%.0f mm", focal.doubleValue)))
            }
            if let bias = exif?[kCGImagePropertyExifExposureBiasValue] as? NSNumber {
                rows.append(InfoRow(key: "曝光补偿", value: String(format: "%+.1f EV", bias.doubleValue)))
            }
            if let profile = props[kCGImagePropertyProfileName] as? String {
                rows.append(InfoRow(key: "色彩配置", value: profile))
            }
        }
    }

    rows.append(InfoRow(key: "大小", value: sizeText))
    if let created {
        rows.append(InfoRow(key: "创建时间", value: LocalFileInfoDateFormatter.string(from: created)))
    }
    if let modified {
        rows.append(InfoRow(key: "修改时间", value: LocalFileInfoDateFormatter.string(from: modified)))
    }
    rows.append(InfoRow(key: "存储位置", value: url.deletingLastPathComponent().path))
    return LocalFileInfo(rows: rows)
}

private let LocalFileInfoDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
}()

private func formattedDuration(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    let h = s / 3600
    let m = (s % 3600) / 60
    let sec = s % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, sec)
    }
    return String(format: "%02d:%02d", m, sec)
}

/// 本地文件详情页（支持空态）
struct LocalFileInfoView: View {
    let info: LocalFileInfo?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let info, !info.rows.isEmpty {
                    List {
                        ForEach(info.rows) { row in
                            LabeledContent(row.key, value: row.value)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在读取详情…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
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

/// 相册资产详情（PHAsset）
struct AssetInfoView: View {
    let info: [String: String]?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let info, !info.isEmpty {
                    List {
                        ForEach(info.keys.sorted(), id: \.self) { key in
                            LabeledContent(key, value: info[key] ?? "—")
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在读取详情…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
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
