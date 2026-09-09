import SwiftUI

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
    }
}
