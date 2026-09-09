import SwiftUI
import UIKit

/// 支持双指缩放、双击放大/还原的图片视图
struct ZoomableImageView: View {
    let image: UIImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let newScale = max(1.0, min(5.0, lastScale * value))
                        scale = newScale
                    }
                    .onEnded { _ in
                        lastScale = scale
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if scale > 1.0 {
                        scale = 1.0
                        lastScale = 1.0
                    } else {
                        scale = 2.5
                        lastScale = 2.5
                    }
                }
            }
    }
}
