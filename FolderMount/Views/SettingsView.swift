import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var listVM: MountListViewModel
    @EnvironmentObject private var store: MountStore
    @State private var showClearConfirm = false

    private let version = "1.0.0"

    var body: some View {
        NavigationStack {
            List {
                Section("连接") {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("断开所有挂载", systemImage: "eject.fill")
                    }
                    .disabled(store.mounts.isEmpty)
                }

                Section("支持的协议") {
                    protocolRow(icon: "network", color: .blue, title: "SMB",
                                detail: "Windows 共享 / NAS / macOS 共享，局域网 IP 直连")
                    protocolRow(icon: "globe.asia.australia", color: .orange, title: "WebDAV",
                                detail: "群晖 / Nextcloud / 坚果云 / 自建服务器")
                }

                Section("关于挂载") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("什么是“本地挂载”？")
                            .font(.subheadline.weight(.semibold))
                        Text("受 iOS 沙盒机制限制，本应用在应用内为每个服务器创建挂载点：连接后即可像浏览本地文件夹一样浏览、下载、上传、重命名与删除局域网共享中的文件。密码保存在本机钥匙串，映射配置仅存于本机。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("关于") {
                    LabeledContent("版本", value: version)
                    LabeledContent("数据存储", value: "仅本机（钥匙串 + 沙盒文档）")
                    Link(destination: URL(string: "https://github.com")!) {
                        Label("GitHub 仓库", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
            }
            .navigationTitle("设置")
            .confirmationDialog("断开所有挂载？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("全部断开", role: .destructive) {
                    listVM.disconnectAll()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("已下载到本地的文件不受影响。")
            }
        }
    }

    private func protocolRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
