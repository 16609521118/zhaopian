import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// UIKit 原生文档选择器的 SwiftUI 包装（参照软件同款实现，规避 SwiftUI fileImporter 在 iPhone 真机的已知 bug）
struct UIKitDocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let allowsMultipleSelection: Bool
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes,
            asCopy: false
        )
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: UIKitDocumentPicker

        init(_ parent: UIKitDocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}
