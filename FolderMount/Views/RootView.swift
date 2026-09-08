import SwiftUI

struct RootView: View {
    @StateObject private var mountStore: MountStore
    @StateObject private var transferVM: TransferViewModel
    @StateObject private var listVM: MountListViewModel

    init() {
        let store = MountStore()
        _mountStore = StateObject(wrappedValue: store)
        _transferVM = StateObject(wrappedValue: TransferViewModel())
        _listVM = StateObject(wrappedValue: MountListViewModel(store: store))
    }

    var body: some View {
        TabView {
            MountListView()
                .tabItem { Label("映射", systemImage: "externaldrive.badge.icloud") }

            TransferView()
                .tabItem { Label("传输", systemImage: "arrow.up.arrow.down") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .environmentObject(mountStore)
        .environmentObject(transferVM)
        .environmentObject(listVM)
    }
}
