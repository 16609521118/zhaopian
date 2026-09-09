import SwiftUI

struct ContentView: View {
    @StateObject private var libraryVM = LibraryViewModel()
    @StateObject private var folderVM = FolderViewModel()

    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("相册", systemImage: "photo.on.rectangle.angled")
                }

            MyImagesView()
                .tabItem {
                    Label("我的图片", systemImage: "folder")
                }

            MountedFoldersView()
                .tabItem {
                    Label("文件夹", systemImage: "externaldrive")
                }
        }
        .environmentObject(libraryVM)
        .environmentObject(folderVM)
    }
}
