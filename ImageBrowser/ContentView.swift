import SwiftUI

struct ContentView: View {
    @StateObject private var folderVM = FolderViewModel()

    var body: some View {
        NavigationStack {
            FolderListView()
                .environmentObject(folderVM)
        }
    }
}

/// 挂载列表（主界面）：显示已挂载的本地文件夹
struct FolderListView: View {
    @EnvironmentObject private var vm: FolderViewModel
    @State private var showForm = false

    var body: some View {
        Group {
            if vm.folders.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("还没有挂载文件夹")
                        .font(.headline)
                    Text("点击右上角 + 添加本地文件夹\n可选择「我的 iPhone」或 iCloud 云盘中的文件夹")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
            } else {
                List {
                    ForEach(vm.folders) { folder in
                        NavigationLink(value: folder) {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(folder.name)
                                        .font(.body)
                                    Text(folder.url.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets {
                            vm.remove(vm.folders[i])
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("本地")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加本地文件夹")
            }
        }
        .sheet(isPresented: $showForm) {
            MountFormView()
                .environmentObject(vm)
        }
        .navigationDestination(for: MountedFolder.self) { folder in
            FolderBrowserView(root: folder.url)
        }
    }
}
