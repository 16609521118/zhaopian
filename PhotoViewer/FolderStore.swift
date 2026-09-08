//
//  FolderStore.swift
//  PhotoViewer
//
//  数据层：通过 UIDocumentPickerViewController（文件多选模式）获取媒体文件的
//  安全作用域 URL，逐文件生成书签持久化。重启后仍可原位访问，不复制文件。
//
//  为什么不用文件夹选择器：iOS 26 上 UIDocumentPickerViewController 的
//  文件夹模式"打开"按钮存在系统缺陷（无响应/置灰，Apple 论坛 806694 等多帖
//  确认，DTS 工程师称 iOS 26 只对"应用可写"目录启用打开）。文件多选模式不受影响。
//

import Foundation
import UniformTypeIdentifiers
import AVFoundation
import UIKit

// MARK: - 模型

struct MountedFile: Codable, Hashable {
    let relativePath: String   // 文件名（同一挂载组内唯一）
    let bookmarkData: Data
}

struct MountedFolder: Codable, Identifiable, Hashable {
    let id: String
    let name: String           // 取自所选文件所在的父目录名
    let files: [MountedFile]
}

enum MediaType {
    case image
    case video
}

struct MediaItem: Identifiable, Hashable {
    let id: String
    let name: String
    let relativePath: String
    let type: MediaType
    let size: Int
}

// MARK: - 存储

final class FolderStore {

    static let shared = FolderStore()

    private(set) var folders: [MountedFolder] = []
    private let defaults = UserDefaults.standard
    private let storageKey = "mountedFolders.v5"

    /// 已解析的文件 URL 缓存（relativePath 全局唯一，用 "folderId|rel" 做 key）
    private var resolvedURLs: [String: URL] = [:]

    /// 缩略图内存缓存
    private let thumbCache = NSCache<NSString, UIImage>()

    private init() { load() }

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

    // MARK: - 挂载（文件多选）

    /// 从文件选择器返回的多个安全作用域 URL 创建逐文件书签，保存为一个挂载组。
    @discardableResult
    func mount(urls: [URL]) throws -> MountedFolder {
        var mountedFiles: [MountedFile] = []
        var folderName = "导入的文件"

        for (idx, url) in urls.enumerated() {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let bookmark = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let filename = url.lastPathComponent
            mountedFiles.append(MountedFile(relativePath: filename, bookmarkData: bookmark))

            // 用第一个文件的父目录名作为挂载组名称
            if idx == 0 {
                folderName = url.deletingLastPathComponent().lastPathComponent
                if folderName.isEmpty { folderName = "导入的文件" }
            }
        }

        guard !mountedFiles.isEmpty else {
            throw NSError(domain: "PhotoViewer", code: 1, userInfo: [NSLocalizedDescriptionKey: "未选择任何文件"])
        }

        let folder = MountedFolder(id: UUID().uuidString, name: folderName, files: mountedFiles)
        folders.append(folder)
        persist()
        return folder
    }

    func unmount(id: String) {
        // 释放该组所有已解析 URL 的安全作用域访问
        if let folder = folders.first(where: { $0.id == id }) {
            for file in folder.files {
                let key = cacheKey(folderId: id, rel: file.relativePath)
                if let url = resolvedURLs[key] {
                    url.stopAccessingSecurityScopedResource()
                    resolvedURLs[key] = nil
                }
            }
        }
        folders.removeAll { $0.id == id }
        persist()
    }

    // MARK: - 书签解析与文件访问

    /// 解析书签并返回文件 URL（不自动 startAccessing，调用方按需启停）。
    func fileURL(for item: MediaItem, in folder: MountedFolder) -> URL? {
        let key = cacheKey(folderId: folder.id, rel: item.relativePath)
        if let url = resolvedURLs[key] { return url }

        guard let file = folder.files.first(where: { $0.relativePath == item.relativePath }) else {
            return nil
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: file.bookmarkData,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        if isStale, let idx = folder.files.firstIndex(where: { $0.relativePath == item.relativePath }) {
            // 书签过期：用当前 URL 重建
            let acc = url.startAccessingSecurityScopedResource()
            if let newBookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil),
               let folderIdx = folders.firstIndex(where: { $0.id == folder.id }) {
                var updatedFiles = folders[folderIdx].files
                updatedFiles[idx] = MountedFile(relativePath: item.relativePath, bookmarkData: newBookmark)
                folders[folderIdx] = MountedFolder(id: folder.id, name: folder.name, files: updatedFiles)
                persist()
            }
            if acc { url.stopAccessingSecurityScopedResource() }
        }
        resolvedURLs[key] = url
        return url
    }

    // MARK: - 媒体枚举

    func media(in folder: MountedFolder) -> [MediaItem] {
        var items: [MediaItem] = []
        for file in folder.files {
            guard let type = Self.mediaType(for: file.relativePath) else { continue }
            // 解析书签获取文件大小（不启动访问，仅取元数据）
            var size = 0
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: file.bookmarkData, bookmarkDataIsStale: &isStale),
               let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                size = (attrs[.size] as? NSNumber)?.intValue ?? 0
            }
            items.append(MediaItem(
                id: file.relativePath,
                name: file.relativePath,
                relativePath: file.relativePath,
                type: type,
                size: size
            ))
        }
        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func mediaType(for filename: String) -> MediaType? {
        let ext = (filename as NSString).pathExtension.lowercased()
        if ["mp4","mov","m4v","3gp","avi","mkv","webm"].contains(ext) { return .video }
        if ["jpg","jpeg","png","gif","webp","bmp","heic","heif","tiff","tif"].contains(ext) { return .image }
        return nil
    }

    // MARK: - 缩略图（内部管理安全作用域启停）

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
            let accessing = url.startAccessingSecurityScopedResource()
            let image: UIImage?
            if item.type == .image {
                image = Self.downsample(imageAt: url, maxPixelSize: max(size.width, size.height) * UIScreen.main.scale)
            } else {
                image = Self.videoThumbnail(url: url, maxSize: size)
            }
            if accessing { url.stopAccessingSecurityScopedResource() }

            if let image = image {
                self.thumbCache.setObject(image, forKey: key)
            }
            DispatchQueue.main.async { completion(image) }
        }
    }

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

    // MARK: - 工具

    private func cacheKey(folderId: String, rel: String) -> String {
        return "\(folderId)|\(rel)"
    }
}
