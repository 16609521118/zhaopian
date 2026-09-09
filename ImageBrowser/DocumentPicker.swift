import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// 系统文档选择器（原生 UIDocumentPickerViewController 包装）
/// 替代 SwiftUI fileImporter：
/// - 在 TabView + NavigationStack 中关闭后不会重置导航/跳 Tab（iOS 16 fileImporter 已知缺陷）
/// - 真正支持选择文件夹（contentTypes 传 [.folder]）
struct DocumentPicker: UIViewControllerRepresentable {
    var contentTypes: [UTType]
    var allowsMultipleSelection: Bool
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        vc.allowsMultipleSelection = allowsMultipleSelection
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls)
        }
    }
}
