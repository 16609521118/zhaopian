import SwiftUI

struct TransferView: View {
    @EnvironmentObject private var transferVM: TransferViewModel

    var body: some View {
        NavigationStack {
            Group {
                if transferVM.activeTasks.isEmpty && transferVM.history.isEmpty {
                    emptyState
                } else {
                    List {
                        if !transferVM.activeTasks.isEmpty {
                            Section("进行中") {
                                ForEach(transferVM.activeTasks) { task in
                                    TransferRowView(task: task)
                                }
                            }
                        }
                        if !transferVM.history.isEmpty {
                            Section("历史记录") {
                                ForEach(transferVM.history) { task in
                                    TransferHistoryRow(task: task)
                                }
                                .onDelete { indexSet in
                                    for idx in indexSet {
                                        transferVM.remove(transferVM.history[idx])
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            if !transferVM.history.isEmpty {
                                Button("清除历史") {
                                    transferVM.clearHistory()
                                }
                                .font(.footnote)
                            }
                        }
                    }
                }
            }
            .navigationTitle("传输")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.system(size: 54))
                .foregroundStyle(.tertiary)
            Text("暂无传输任务")
                .font(.headline)
            Text("在挂载的文件浏览器中选择文件下载，\n或从「文件」上传到服务器。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Active row

private struct TransferRowView: View {
    @EnvironmentObject private var transferVM: TransferViewModel
    let task: TransferTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: task.direction == .download ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .foregroundStyle(task.direction == .download ? .blue : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.remotePath)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text("\(task.direction == .download ? "下载" : "上传") · \(task.mountName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    transferVM.cancel(task)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            ProgressView(value: task.progress)
                .tint(task.status == .failed ? .red : .accentColor)
            HStack {
                Text(task.statusText)
                Spacer()
                if task.totalBytes > 0 {
                    Text("\(Formatters.fileSize(task.transferredBytes)) / \(Formatters.fileSize(task.totalBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - History row

private struct TransferHistoryRow: View {
    let task: TransferTask

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.system(size: 20))
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.remotePath)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(task.direction == .download ? "下载" : "上传") · \(task.mountName)")
                    if task.totalBytes > 0 {
                        Text("· \(Formatters.fileSize(task.totalBytes))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if task.status == .failed, let msg = task.errorMessage {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: 160, alignment: .trailing)
            } else {
                Text(task.statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusIcon: String {
        switch task.status {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .cancelled: return "minus.circle.fill"
        default: return "clock"
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        default: return .secondary
        }
    }
}
