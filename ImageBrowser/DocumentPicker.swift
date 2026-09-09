import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// 系统文档选择器（全局 presenter 模式）
///
/// 直接通过 UIDocumentPickerViewController 从最上层控制器 present，
/// 不依赖 SwiftUI .sheet 的生命周期 —— 在 TabView + NavigationStack 中
/// 也能保证 delegate 回调（didPickDocumentsAt）一定触发，选完即回调。
final class DocumentPickerPresenter: NSObject, UIDocumentPickerDelegate {
    static let shared = DocumentPickerPresenter()

    private var picker: UIDocumentPickerViewController?
    private var onPick: (([URL]) -> Void)?

    private override init() {
        super.init()
    }

    func present(contentTypes: [UTType], allowsMultipleSelection: Bool, onPick: @escaping ([URL]) -> Void) {
        guard picker == nil else { return } // 防止重复弹出
        self.onPick = onPick
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = self
        self.picker = picker
        if let top = Self.topViewController() {
            top.present(picker, animated: true)
        } else {
            self.onPick = nil
            self.picker = nil
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let callback = onPick
        onPick = nil
        picker = nil
        callback?(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        onPick = nil
        picker = nil
    }

    /// 找到当前最上层的视图控制器（处理多层 presented）
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let root = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
