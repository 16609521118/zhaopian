import SwiftUI
import Photos
import UIKit

/// 全屏查看页：左右滑动翻页，支持分享与保存
struct ImageDetailView: View {
    @EnvironmentObject private var vm: LibraryViewModel
    @State private var currentIndex: Int
    @State private var currentImage: UIImage?
    @State private var showShare = false
    @State private var showSaved = false
    @State private var saving = false

    init(startIndex: Int) {
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(vm.assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                    FullImageView(asset: asset)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack {
                Spacer()
                HStack(spacing: 24) {
                    Text("\(currentIndex + 1) / \(vm.assets.count)")
                        .font(.footnote.monospacedDigit())
                    Spacer()
                    Button {
                        showShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(currentImage == nil)
                    .accessibilityLabel("分享")

                    Button {
                        saveCurrent()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .disabled(currentImage == nil || saving)
                    .accessibilityLabel("保存到相册")
                }
                .font(.title3)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(.bottom, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showShare) {
            if let currentImage {
                ActivityView(items: [currentImage])
            }
        }
        .alert("已保存到相册", isPresented: $showSaved) {
            Button("好", role: .cancel) {}
        }
        .task(id: currentIndex) {
            guard vm.assets.indices.contains(currentIndex) else { return }
            currentImage = await vm.requestFullImage(for: vm.assets[currentIndex])
        }
    }

    private func saveCurrent() {
        guard let image = currentImage else { return }
        saving = true
        Task {
            let ok = await vm.saveImageToLibrary(image)
            await MainActor.run {
                saving = false
                if ok {
                    showSaved = true
                }
            }
        }
    }
}

/// 单页全屏图片（按需加载原图）
struct FullImageView: View {
    let asset: PHAsset
    @EnvironmentObject private var vm: LibraryViewModel
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                ZoomableImageView(image: image)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task(id: asset.localIdentifier) {
            if image == nil {
                image = await vm.requestFullImage(for: asset)
            }
        }
    }
}
