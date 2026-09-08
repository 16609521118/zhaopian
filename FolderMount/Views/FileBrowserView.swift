import SwiftUI

struct FileBrowserView: View {
    @StateObject private var vm: FileBrowserViewModel
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var showUploadPicker = false
    @State private var showDeleteConfirm = false
    @State private var pendingDelete: RemoteItem?
    @State private var showRename = false
    @State private var renameTarget: RemoteItem?
    @State private var renameText = ""
    @State private var showMove = false
    @State private var moveTarget: RemoteItem?

    init(mount: Mount, service: RemoteFileSystem, transferVM: TransferViewModel) {
        _vm = StateObject(wrappedValue: FileBrowserViewModel(mount: mount, service: service, transferVM: transferVM))
    }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            Divider()
            content
        }
        .navigationTitle(vm.mount.name.isEmpty ? vm.mount.host : vm.mount.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await vm.refresh() }
        .alert("发生错误", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .alert("新建文件夹", isPresented: $showNewFolder) {
            TextField("文件夹名称", text: $newFolderName)
            Button("创建") {
                let name = newFolderName.trimmingCharacters(in: .whitespaces)
                Task { await vm.createDirectory(name: name) }
                newFolderName = ""
            }
            Button("取消", role: .cancel) { newFolderName = "" }
        }
        .fileImporter(isPresented: $showUploadPicker, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            handleUpload(result)
        }
        .confirmationDialog("删除项目？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let item = pendingDelete {
                    Task { await vm.delete(item) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(pendingDelete?.name ?? "")
        }
        .alert("重命名", isPresented: $showRename) {
            TextField("新名称", text: $renameText)
            Button("确定") {
                if let item = renameTarget {
                    let name = renameText.trimmingCharacters(in: .whitespaces)
                    Task { await vm.rename(item, to: name) }
                }
                renameTarget = nil
            }
            Button("取消", role: .cancel) { renameTarget = nil }
        }
        .sheet(item: $moveTarget) { item in
            DirectoryPickerView(mount: vm.mount, service: vm.service, title: "移动到…") { directory in
                Task { await vm.move(item, to: directory) }
            }
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button {
                    vm.popToRoot()
                } label: {
                    Label("根目录", systemImage: "house")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.borderless)
                ForEach(Array(vm.pathComponents.enumerated()), id: \.offset) { index, comp in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Button {
                        vm.popTo(index)
                    } label: {
                        Text(comp)
                            .font(.footnote.weight(.medium))
                            .lineLimit(1)
                    }
                    .buttonStyle(.borderless)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.items.isEmpty {
            ProgressView("加载目录…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.items.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("空文件夹")
                    .foregroundStyle(.secondary)
                if !vm.isAtRoot {
                    Button("返回上级") { vm.popTo(vm.pathComponents.count - 2) }
                        .font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(vm.items) { item in
                    FileRowView(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if item.isDirectory { vm.push(item.name) }
                        }
                        .contextMenu { contextMenu(for: item) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = item
                                showDeleteConfirm = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                renameTarget = item
                                renameText = item.name
                                showRename = true
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            .tint(.orange)
                            if !item.isDirectory {
                                Button {
                                    Task { await vm.download(item) }
                                } label: {
                                    Label("下载", systemImage: "arrow.down.circle")
                                }
                                .tint(.blue)
                            }
                        }
                }
            }
            .listStyle(.plain)
            .refreshable { await vm.refresh() }
            .overlay(alignment: .bottom) {
                if let notice = vm.noticeMessage {
                    Text(notice)
                        .font(.footnote)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 8)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                vm.noticeMessage = nil
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: RemoteItem) -> some View {
        if item.isDirectory {
            Button {
                vm.push(item.name)
            } label: {
                Label("打开", systemImage: "folder")
            }
            Button {
                moveTarget = item
            } label: {
                Label("移动到…", systemImage: "folder.badge.gearshape")
            }
            Button {
                renameTarget = item
                renameText = item.name
                showRename = true
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button(role: .destructive) {
                pendingDelete = item
                showDeleteConfirm = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        } else {
            Button {
                Task { await vm.download(item) }
            } label: {
                Label("下载到本地", systemImage: "arrow.down.circle")
            }
            Button {
                renameTarget = item
                renameText = item.name
                showRename = true
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button {
                moveTarget = item
            } label: {
                Label("移动到…", systemImage: "folder.badge.gearshape")
            }
            Button(role: .destructive) {
                pendingDelete = item
                showDeleteConfirm = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await vm.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("刷新")
            Menu {
                Button {
                    showNewFolder = true
                } label: {
                    Label("新建文件夹", systemImage: "folder.badge.plus")
                }
                Button {
                    showUploadPicker = true
                } label: {
                    Label("上传文件…", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("更多操作")
        }
    }

    private func handleUpload(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                let gotAccess = url.startAccessingSecurityScopedResource()
                defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }
                Task { await vm.upload(url: url) }
            }
        case .failure(let error):
            vm.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Directory picker for move

private struct DirectoryPickerView: View {
    let mount: Mount
    let service: RemoteFileSystem
    let title: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentPath = "/"
    @State private var directories: [RemoteItem] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        currentPath = "/"
                        Task { await load() }
                    } label: {
                        Label("根目录", systemImage: "house")
                    }
                    ForEach(directories) { dir in
                        Button {
                            currentPath = dir.path
                            Task { await load() }
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundStyle(.blue)
                                Text(dir.name)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                } header: {
                    Text("选择目标文件夹")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("移动到这里") {
                        onSelect(currentPath)
                        dismiss()
                    }
                }
            }
            .task { await load() }
            .alert("错误", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let items = try await service.listDirectory(at: currentPath)
            directories = items.filter(\.isDirectory)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
