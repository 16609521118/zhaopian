import SwiftUI

@main
struct FolderMountApp: App {
    @StateObject private var mountStore = MountStore()
    @StateObject private var transferVM = TransferViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(mountStore)
                .environmentObject(transferVM)
                .tint(Color.accentColor)
        }
    }
}
