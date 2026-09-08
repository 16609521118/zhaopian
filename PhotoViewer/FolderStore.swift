//
//  FolderStore.swift
//  PhotoViewer
//
//  核心数据层：通过 UIDocumentPickerViewController 获取安全作用域 URL，
//  生成书签持久化，重启后仍可访问原文件夹（真正的原位挂载，不复制文件）。
//  提供媒体枚举、缩略图生成（图片 downsample + 视频 AVAssetImageGenerator）。
//

import Foundation
import UniformTypeIdentifiers
import AVFoundation
import UIKit

// MARK: - 模型

struct MountedFolder: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let bookmarkData: Data
}

enum MediaType {
    case image
    case video
}

struct MediaItem: Identifiable, Hashable {
    let id: String          // 相对路径作为唯一 id
    let name: String
    let relativePath: String
    let type: MediaType
    let size: Int
}

// MARK: - 存储与访问

final class FolderStore {

    static let shared = FolderStore()

    private(set) var folders: [MountedFolder] = []
    private let defaults = UserDefaults.standard
    private let storageKey = "mountedFolders.v4"

    /// 已启动安全作用域访问的文件夹 URL（folderId → URL），保持访问态直到 release
    private var activeURLs: [String: URL] = [:]

    /// 媒体枚举缓存（folderId → [MediaItem]），避免重复遍历
    private var mediaCache: [String: [MediaItem]] = [:]

    /// 缩略图内存缓存
    private let thumbCache = NSCache<NSString, UIImage>()

    private init() {
        load()
    }

    // MARK: - 持久化

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([MountedFolder].self, from: data) else {
            folders = []
            return
        }
        folders = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(folders) {
            defaults.set(data, forKey: storageKey)
        }
    }

    // MARK: - 挂载 / 卸载

    /// 从文件选择器返回的安全作用域 URL 创建书签并保存
    @discardableResult
    func mount(url: URL) throws -> MountedFolder {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // iOS 上用 .minimalBookmark（withSecurityScope 在 iOS 不可用），
        // 解析出的 URL 仍是安全作用域 URL。
        let bookmark = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let folder = MountedFolder(
            id: UUID().uuidString,
            name: url.lastPathComponent,
            bookmarkData: bookmark
        )
        folders.append(folder)
        persist()
        return folder
    }

    func unmount(id: String) {
        if let url = activeURLs[id] {
            url.stopAccessingSecurityScopedResource()
            activeURLs[id] = nil
        }
        mediaCache[id] = nil
        folders.removeAll { $0.id == id }
        persist()
    }

    // MARK: - 书签解析与访问

    /// 解析书签并启动安全作用域访问；返回 nil 表示书签失效或无法访问。
    /// 多次调用同一文件夹只启动一次，直到 releaseFolder。
    @discardableResult
    func access(_ folder: MountedFolder) -> URL? {
        if let url = activeURLs[folder.id] { return url }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: folder.bookmarkData,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        // 书签过期：用当前 URL 重建书签
        if isStale {
            let acc = url.startAccessingSecurityScopedResource()
            if let newBookmark = try? url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ), let idx = folders.firstIndex(where: { $0.id == folder.id }) {
                folders[idx] = MountedFolder(id: folder.id, name: folder.name, bookmarkData: newBookmark)
                persist()
            }
            if acc { url.stopAccessingSecurityScopedResource() }
        }

        guard url.startAccessingSecurityScopedResource() else { return nil }
        activeURLs[folder.id] = url
        return url
    }

    func release(_ folder: MountedFolder) {
        if let url = activeURLs[folder.id] {
            url.stopAccessingSecurityScopedResource()
            activeURLs[folder.id] = nil
        }
    }

    // MARK: - 媒体枚举

    func media(in folder: MountedFolder) -> [MediaItem] {
        if let cached = mediaCache[folder.id] { return cached }
        guard let url = access(folder) else {
            mediaCache[folder.id] = []
            return []
        }
        let items = enumerate(in: url, prefix: "")
        mediaCache[folder.id] = items
        return items
    }

    func invalidateCache(for folderId: String) {
        mediaCache[folderId] = nil
    }

    private func enumerate(in folderURL: URL, prefix: String) -> [MediaItem] {
        let fm = FileManager.default
        var items: [MediaItem] = []
        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return items }

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            let filename = fileURL.lastPathComponent
            guard let type = Self.mediaType(for: filename) else { continue }
            let rel = prefix.isEmpty ? filename : "\(prefix)/\(filename)"
            items.append(MediaItem(
                id: rel,
                name: filename,
                relativePath: rel,
                type: type,
                size: values.fileSize ?? 0
            ))
        }
        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 获取媒体文件的真实文件 URL（需文件夹已 access）
    func fileURL(for item: MediaItem, in folder: MountedFolder) -> URL? {
        guard let folderURL = access(folder) else { return nil }
        return folderURL.appendingPathComponent(item.relativePath)
    }

    private static func mediaType(for filename: String) -> MediaType? {
        let ext = (filename as NSString).pathExtension.lowercased()
        if ["mp4","mov","m4v","3gp","avi","mkv","webm"].contains(ext) { return .video }
        if ["jpg","jpeg","png","gif","webp","bmp","heic","heif","tiff","tif"].contains(ext) { return .image }
        return nil
    }

    // MARK: - 缩略图

    func thumbnail(for item: MediaItem, in folder: MountedFolder, size: CGSize,
                   completion: @escaping (UIImage?) -> Void) {
        let key = "\(folder.id)|\(item.relativePath)|\(Int(size.width))x\(Int(size.height))" as NSString
        if let cached = thumbCache.object(forKey: key) {
            completion(cached)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let url = self.fileURL(for: item, in: folder) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let image: UIImage?
            if item.type == .image {
                image = Self.downsample(imageAt: url, maxPixelSize: max(size.width, size.height) * UIScreen.main.scale)
            } else {
                image = Self.videoThumbnail(url: url, maxSize: size)
            }
            if let image = image {
                self.thumbCache.setObject(image, forKey: key)
            }
            DispatchQueue.main.async { completion(image) }
        }
    }

    /// 大图降采样（ImageIO，避免直接 UIImage(contentsOfFile:) 占满内存）
    private static func downsample(imageAt url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func videoThumbnail(url: URL, maxSize: CGSize) -> UIImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
