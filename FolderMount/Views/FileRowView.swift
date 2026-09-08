import SwiftUI

struct FileRowView: View {
    let item: RemoteItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 22))
                .foregroundStyle(iconColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(1)
                if !item.isDirectory {
                    HStack(spacing: 6) {
                        Text(item.displaySize)
                        if !item.displayModified.isEmpty {
                            Text("·")
                            Text(item.displayModified)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }

    private var iconName: String {
        if item.isDirectory { return "folder.fill" }
        switch (item.name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "svg", "tiff":
            return "photo.fill"
        case "mp4", "mov", "mkv", "avi", "webm", "m4v":
            return "film.fill"
        case "mp3", "wav", "flac", "aac", "m4a", "ogg":
            return "music.note"
        case "pdf":
            return "doc.richtext.fill"
        case "doc", "docx", "pages":
            return "doc.text.fill"
        case "xls", "xlsx", "numbers", "csv":
            return "tablecells.fill"
        case "ppt", "pptx", "key":
            return "chart.bar.doc.horizontal.fill"
        case "zip", "rar", "7z", "tar", "gz":
            return "archivebox.fill"
        case "txt", "md", "log":
            return "doc.plaintext.fill"
        default:
            return "doc.fill"
        }
    }

    private var iconColor: Color {
        if item.isDirectory { return .blue }
        switch (item.name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "svg", "tiff":
            return .green
        case "mp4", "mov", "mkv", "avi", "webm", "m4v":
            return .pink
        case "mp3", "wav", "flac", "aac", "m4a", "ogg":
            return .purple
        case "zip", "rar", "7z", "tar", "gz":
            return .orange
        default:
            return .secondary
        }
    }
}
