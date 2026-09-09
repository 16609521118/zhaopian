import Foundation
import Photos
import UIKit

/// 相册数据层：负责照片库权限、资产加载、缩略图/原图请求与保存。
final class LibraryViewModel: NSObject, ObservableObject {
    @Published var assets: [PHAsset] = []
    @Published var isAuthorized = false
    @Published var isLoading = false

    private let imageManager = PHCachingImageManager()

    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
        refreshAuthorization()
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    // MARK: - 权限

    func refreshAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                DispatchQueue.main.async {
                    self?.isAuthorized = Self.isGranted(newStatus)
                    if self?.isAuthorized == true {
                        self?.loadAssets()
                    }
                }
            }
        default:
            isAuthorized = Self.isGranted(status)
            if isAuthorized {
                loadAssets()
            }
        }
    }

    private static func isGranted(_ status: PHAuthorizationStatus) -> Bool {
        status == .authorized || status == .limited
    }

    // MARK: - 加载

    func loadAssets() {
        isLoading = true
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetch = PHAsset.fetchAssets(with: .image, options: options)
        var result: [PHAsset] = []
        result.reserveCapacity(fetch.count)
        fetch.enumerateObjects { asset, _, _ in
            result.append(asset)
        }
        assets = result
        isLoading = false
    }

    // MARK: - 图片请求

    func requestThumbnail(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            var resumed = false
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                if !resumed {
                    resumed = true
                    continuation.resume(returning: image)
                }
            }
        }
    }

    func requestFullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            var resumed = false
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .none
            options.isNetworkAccessAllowed = true
            imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                if !resumed {
                    resumed = true
                    continuation.resume(returning: image)
                }
            }
        }
    }

    // MARK: - 保存

    @discardableResult
    func saveImageToLibrary(_ image: UIImage) async -> Bool {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return true
        } catch {
            return false
        }
    }
}

extension LibraryViewModel: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in
            self?.loadAssets()
        }
    }
}
