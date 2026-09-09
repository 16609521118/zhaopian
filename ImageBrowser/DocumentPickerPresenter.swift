import UIKit
import UniformTypeIdentifiers

/// UIKit 原生文档/文件夹选择器：直接全屏模态 present（参照软件 Lumenic 同款呈现方式）
final class DocumentPickerPresenter: NSObject, UIDocumentPickerDelegate {
    static let shared = DocumentPickerPresenter()

    private var onPick: (([URL]) -> Void)?
    private var onCancel: (() -> Void)?

    private override init() {
        super.init()
    }

    func present(
        contentTypes: [UTType],
        allowsMultipleSelection: Bool,
        onPick: @escaping ([URL]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onPick = onPick
        self.onCancel = onCancel
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes,
            asCopy: false
        )
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = self
        guard let top = Self.topViewController() else { return }
        top.present(picker, animated: true, completion: nil)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let pick = onPick
        onPick = nil
        onCancel = nil
        pick?(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        let cancel = onCancel
        onPick = nil
        onCancel = nil
        cancel?()
    }

    /// 找当前最顶层的控制器（激活场景 → key 窗口 → presentedViewController 链）
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
        var windowScene: UIWindowScene?
        for scene in scenes {
            if let ws = scene as? UIWindowScene, ws.activationState == .foregroundActive {
                windowScene = ws
                break
            }
        }
        if windowScene == nil {
            windowScene = scenes.first as? UIWindowScene
        }
        guard let windowScene else { return nil }
        let window = windowScene.windows.first { $0.isKeyWindow } ?? windowScene.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
