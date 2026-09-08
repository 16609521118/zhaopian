import SwiftUI

struct MountListView: View {
    @EnvironmentObject private var store: MountStore
    @EnvironmentObject private var listVM: MountListViewModel
    @EnvironmentObject private var transferVM: TransferViewModel

    @State private var showAddSheet = false
    @State private var editingMount: Mount?
    @State private var connectingID: UUID?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var pendingDelete: Mount?
    @State private var showDeleteConfirm = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.mounts.isEmpty {
                    emptyState
                } else {
                    mountList
                }
            }
            .navigationTitle("文件夹挂载")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加挂载点")
                }
            }
            .sheet(isPresented: $showAddSheet) {
                MountEditView(mode: .add)
            }
            .sheet(item: $editingMount) { mount in
                MountEditView(mode: .edit(mount))
            }
            .navigationDestination(for: Mount.self) { mount in
                if let service = listVM.session(for: mount) {
                    FileBrowserView(mount: mount, service: service, transferVM: transferVM)
                } else {
                    ProgressView("正在连接 \(mount.displayAddress)…")
                        .task {
                            do {
                                _ = try await listVM.connect(mount)
                                path.append(mount)
                            } catch {
                                errorMessage = error.localizedDescription
                                showError = true
                                path = NavigationPath()
                            }
                        }
                }
            }
            .confirmationDialog("删除挂载点？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let mount = pendingDelete {
                        if listVM.isConnected(mount) { listVM.disconnect(mount) }
                        store.delete(mount)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将同时移除本地保存的密码，已下载文件不会删除。")
            }
            .alert("连接失败", isPresented: $showError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private var mountList: some View {
        List {
            ForEach(store.mounts) { mount in
                MountRowView(
                    mount: mount,
                    isConnected: listVM.isConnected(mount),
                    isConnecting: connectingID == mount.id
                )
                .contentShape(Rectangle())
                .onTapGesture { connect(mount) }
                .contextMenu {
                    Button {
                        editingMount = mount
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        pendingDelete = mount
                        showDeleteConfirm = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDelete = mount
                        showDeleteConfirm = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    Button {
                        editingMount = mount
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    .tint(.orange)
                    if listVM.isConnected(mount) {
                        Button {
                            listVM.disconnect(mount)
                        } label: {
                            Label("断开", systemImage: "eject")
                        }
                        .tint(.gray)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if connectingID != nil {
                ProgressView("正在连接本地服务器…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("还没有挂载点")
                .font(.headline)
            Text("添加一个局域网文件服务器（SMB 或 WebDAV），\n即可通过 IP 直连并像本地文件夹一样浏览管理。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showAddSheet = true
            } label: {
                Label("添加挂载点", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func connect(_ mount: Mount) {
        guard connectingID == nil else { return }
        if listVM.isConnected(mount) {
            path.append(mount)
            return
        }
        connectingID = mount.id
        Task {
            do {
                _ = try await listVM.connect(mount)
                connectingID = nil
                path.append(mount)
            } catch {
                connectingID = nil
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Row

private struct MountRowView: View {
    let mount: Mount
    let isConnected: Bool
    let isConnecting: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(iconColor.opacity(0.16))
                    .frame(width: 46, height: 46)
                Image(systemName: mount.kind == .smb ? "network" : "globe.asia.australia")
                    .font(.system(size: 22))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(mount.name.isEmpty ? mount.displayAddress : mount.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(mount.kind.rawValue)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.15), in: Capsule())
                }
                Text(mount.displayDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            statusView
        }
        .padding(.vertical, 2)
        .opacity(isConnecting ? 0.5 : 1)
    }

    @ViewBuilder
    private var statusView: some View {
        if isConnecting {
            ProgressView()
        } else if isConnected {
            Label("已挂载", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        } else {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
    }

    private var iconColor: Color {
        mount.kind == .smb ? .blue : .orange
    }
}
