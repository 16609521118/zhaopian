import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// 系统文档选择器（全局 presenter，加固版）
///
/// 可靠性设计：
/// 1. 从最上层视图控制器 present，不依赖 SwiftUI sheet 生命周期；
/// 2. 查找 topViewController 带多级 fallback（激活状态、key window）；
/// 3. present 推迟到主队列下一拍执行，避开手势/动画时序；
/// 4. 重复调用先清理旧 picker，绝不静默吞掉点击；
/// 5. didPickDocumentsAt 同步回调（security scope 在回调内最可靠）。
final class DocumentPickerPresenter: NSObject, UIDocumentPickerDelegate {
    static let shared = DocumentPickerPresenter()

    private var picker: UIDocumentPickerViewController?
    private var onPick: (([URL]) -> Void)?

    private override init() {
        super.init()
    }

    func present(contentTypes: [UTType], allowsMultipleSelection: Bool, onPick: @escaping ([URL]) -> Void) {
        // 清理可能残留的旧选择器，避免点击被静默丢弃
        if let old = picker {
            old.dismiss(animated: false)
        }
        picker = nil
        self.onPick = onPick

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = self
        self.picker = picker

        guard let top = Self.topViewController() else {
            self.onPick = nil
            self.picker = nil
            return
        }
        DispatchQueue.main.async {
            top.present(picker, animated: true)
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

    /// 找到当前最上层的视图控制器（多级 fallback）
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first else {
            return nil
        }
        var top = window.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
