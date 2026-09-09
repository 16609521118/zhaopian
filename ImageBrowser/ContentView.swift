import SwiftUI
import UIKit

/// 我的图片目录有变化（分享导入等）时通知刷新
extension Notification.Name {
    static let myImagesDidChange = Notification.Name("myImagesDidChange")
}



/// 全局 Tab 切换：导入/挂载完成后自动跳回对应页面
final class TabRouter: ObservableObject {
    @Published var selection = 0
}

struct ContentView: View {
    @StateObject private var libraryVM = LibraryViewModel()
    @StateObject private var folderVM = FolderViewModel()
    @StateObject private var tabRouter = TabRouter()

    var body: some View {
        TabView(selection: $tabRouter.selection) {
            LibraryView()
                .tabItem {
                    Label("相册", systemImage: "photo.on.rectangle.angled")
                }
                .tag(0)

            MyImagesView()
                .tabItem {
                    Label("我的图片", systemImage: "folder")
                }
                .tag(1)

            MountedFoldersView()
                .tabItem {
                    Label("文件夹", systemImage: "externaldrive")
                }
                .tag(2)
        }
        .environmentObject(libraryVM)
        .environmentObject(folderVM)
        .environmentObject(tabRouter)
        .onOpenURL { url in
            handleSharedFile(url)
        }
        .overlay(alignment: .top) {
            if let importToast {
                ToastView(text: importToast)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: importToast)
    }

    @State private var importToast: String?

    /// 从系统任意位置「分享到图览 / 用图览打开」进来的文件：复制进沙盒并刷新
    private func handleSharedFile(_ url: URL) {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Images", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let opened = url.startAccessingSecurityScopedResource()
        defer {
            if opened { url.stopAccessingSecurityScopedResource() }
        }
        let name = url.lastPathComponent
        let dest = dir.appendingPathComponent(name)
        do {
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: url, to: dest)
            try? fm.removeItem(at: url) // 清理系统放置的临时副本
            NotificationCenter.default.post(name: .myImagesDidChange, object: nil)
            withAnimation { importToast = "已导入：\(name)" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { importToast = nil }
            }
            tabRouter.selection = 1
        } catch {
            withAnimation { importToast = "导入失败：\(error.localizedDescription)" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { importToast = nil }
            }
        }
    }
}
