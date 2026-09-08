import SwiftUI

struct MountEditView: View {
    enum Mode {
        case add
        case edit(Mount)
    }

    @EnvironmentObject private var store: MountStore
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var name = ""
    @State private var kind: Mount.Kind = .smb
    @State private var host = ""
    @State private var port = ""
    @State private var path = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isAnonymous = false
    @State private var showPassword = false
    @State private var showSaveError = false
    @State private var saveErrorText = ""

    init(mode: Mode) {
        self.mode = mode
        if case .edit(let mount) = mode {
            _name = State(initialValue: mount.name)
            _kind = State(initialValue: mount.kind)
            _host = State(initialValue: mount.host)
            _port = State(initialValue: String(mount.port))
            _path = State(initialValue: mount.path)
            _username = State(initialValue: mount.username)
            _isAnonymous = State(initialValue: mount.isAnonymous)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("映射信息") {
                    TextField("名称（如 客厅 NAS）", text: $name)
                    Picker("协议", selection: $kind) {
                        ForEach(Mount.Kind.allCases) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    TextField(kind == .smb ? "服务器 IP（如 192.168.1.100）" : "服务器 IP 或域名", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        TextField("端口", text: $port)
                            .keyboardType(.numberPad)
                            .frame(maxWidth: 110)
                        Text(kind == .smb ? "SMB 默认 445" : "WebDAV 默认 5005")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    TextField(kind == .smb ? "共享名（如 Music，可留空列共享）" : "根路径（如 /dav，可留空）", text: $path)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("凭据") {
                    Toggle("匿名访问", isOn: $isAnonymous.animation())
                    if !isAnonymous {
                        TextField("用户名", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        HStack {
                            Group {
                                if showPassword {
                                    TextField("密码", text: $password)
                                } else {
                                    SecureField("密码", text: $password)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button(action: save) {
                        Text(isEditing ? "保存修改" : "添加挂载点")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                    .disabled(!canSave)
                } footer: {
                    Text("密码仅保存在本机钥匙串（Keychain）中，不会上传。")
                }
            }
            .navigationTitle(isEditing ? "编辑挂载点" : "添加挂载点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("无法保存", isPresented: $showSaveError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveErrorText)
            }
        }
    }

    private var canSave: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
            && (Int(port) ?? 0) > 0 && (Int(port) ?? 0) < 65536
    }

    private func save() {
        guard canSave else {
            saveErrorText = "请填写有效的服务器 IP 与端口（1-65535）。"
            showSaveError = true
            return
        }
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let finalName = trimmedName.isEmpty ? trimmedHost : trimmedName
        let portValue = Int(port) ?? kind.defaultPort
        let trimmedPath = path.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let userName = isAnonymous ? "" : username.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .add:
            let mount = Mount(name: finalName, kind: kind, host: trimmedHost,
                              port: portValue, path: trimmedPath,
                              username: userName, isAnonymous: isAnonymous)
            store.add(mount)
            if !isAnonymous, !password.isEmpty {
                store.savePassword(password, for: mount)
            }
        case .edit(let original):
            var updated = original
            updated.name = finalName
            updated.kind = kind
            updated.host = trimmedHost
            updated.port = portValue
            updated.path = trimmedPath
            updated.username = userName
            updated.isAnonymous = isAnonymous
            updated.isConnected = false
            store.update(updated)
            if isAnonymous {
                KeychainHelper.delete(for: updated.keychainAccount)
            } else if !password.isEmpty {
                store.savePassword(password, for: updated)
            }
        }
        dismiss()
    }
}
