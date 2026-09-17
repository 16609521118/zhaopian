import SwiftUI

struct ContentView: View {
    @StateObject private var manager = BookmarkManager.shared
    @State private var currentFolder: URL?
    @State private var currentFolderName: String = ""
    @State private var selectedVideo: URL?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("挂载方式：UIDocumentPicker + Security-Scoped Bookmark（与 SenPlayer 一致）。挂载目录仅在本 App 内可见，不会出现在系统「文件」App 侧边栏。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("已挂载文件夹") {
                    if manager.savedFolders.isEmpty {
                        Text("还没有挂载任何文件夹，点右上角「+」选择目录")
                            .foregroundColor(.secondary)
                    }
                    ForEach(manager.savedFolders) { folder in
                        Button {
                            if let url = manager.resolveFolder(folder) {
                                currentFolder = url
                                currentFolderName = folder.name
                            }
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.accentColor)
                                Text(folder.name)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteFolders)
                }

                if let folder = currentFolder {
                    Section("「\(currentFolderName)」内的视频") {
                        let files = manager.listVideoFiles(in: folder)
                        if files.isEmpty {
                            Text("该目录下没有识别到视频文件")
                                .foregroundColor(.secondary)
                        }
                        ForEach(files, id: \.self) { file in
                            Button {
                                selectedVideo = file
                            } label: {
                                HStack {
                                    Image(systemName: "film")
                                        .foregroundColor(.pink)
                                    Text(file.lastPathComponent)
                                        .lineLimit(1)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("书签媒体播放器")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentPicker()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $selectedVideo) { video in
                VLCPlayerView(url: video)
                    .ignoresSafeArea()
            }
            .onAppear { manager.loadFolders() }
        }
    }

    private func presentPicker() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }
        manager.pickFolder(from: root)
    }

    private func deleteFolders(at offsets: IndexSet) {
        offsets.map { manager.savedFolders[$0] }.forEach { manager.remove($0) }
    }
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}
