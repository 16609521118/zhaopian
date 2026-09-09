import SwiftUI
import UniformTypeIdentifiers

/// Lumenic 同款「添加 本地」配置页：名称 + 挂载目录 + 挂载本地目录按钮
struct MountFormView: View {
    @EnvironmentObject private var vm: FolderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedURL: URL?
    @State private var showPickerAlert = false
    @State private var showPicker = false
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("信息") {
                    TextField("名称（默认文件夹名）", text: $name)
                }

                Section("挂载目录") {
                    HStack {
                        Text(selectedURL?.lastPathComponent ?? "未选择")
                            .foregroundStyle(selectedURL == nil ? .secondary : .primary)
                        Spacer()
                        Button(selectedURL == nil ? "选择文件夹" : "重新选择") {
                            showPickerAlert = true
                        }
                        .buttonStyle(.bordered)
                    }
                    if let selectedURL {
                        Text(selectedURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text("可选择「我的 iPhone」或 iCloud 云盘中的文件夹")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        guard let url = selectedURL else {
                            showToast("请先选择文件夹")
                            return
                        }
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        let finalName = trimmed.isEmpty ? url.lastPathComponent : trimmed
                        if let err = vm.mount(url: url, name: finalName) {
                            showToast(err)
                        } else {
                            dismiss()
                        }
                    } label: {
                        Text("挂载本地目录")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle("添加 本地")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("选择文件夹", isPresented: $showPickerAlert) {
                Button("开始选择") { showPicker = true }
                Button("取消", role: .cancel) {}
            } message: {
                Text("进入目标文件夹后，点右上角蓝色「打开」完成选择")
            }
            .onChange(of: showPicker) { showing in
                if showing {
                    DispatchQueue.main.async {
                        DocumentPickerPresenter.shared.present(
                            contentTypes: [.folder],
                            allowsMultipleSelection: false
                        ) { urls in
                            showPicker = false
                            guard let url = urls.first else { return }
                            selectedURL = url
                            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                                name = url.lastPathComponent
                            }
                            showToast("已选择：" + url.lastPathComponent)
                        } onCancel: {
                            showPicker = false
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                if let toast {
                    ToastView(text: toast)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: toast)
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                if toast == message { toast = nil }
            }
        }
    }
}
