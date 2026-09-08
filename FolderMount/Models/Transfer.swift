import Foundation

/// 一个传输任务（下载 / 上传）。
struct TransferTask: Identifiable, Codable, Equatable {
    enum Direction: String, Codable {
        case download, upload
    }

    enum Status: String, Codable {
        case queued, running, completed, failed, cancelled
    }

    let id: UUID
    var mountName: String
    var direction: Direction
    /// 远程路径
    var remotePath: String
    /// 本地路径（URL 的 path 字符串，便于 Codable）
    var localPath: String
    var totalBytes: Int64
    var transferredBytes: Int64
    var status: Status
    var errorMessage: String?
    let createdAt: Date
    var finishedAt: Date?

    init(id: UUID = UUID(), mountName: String, direction: Direction,
         remotePath: String, localPath: String,
         totalBytes: Int64 = 0) {
        self.id = id
        self.mountName = mountName
        self.direction = direction
        self.remotePath = remotePath
        self.localPath = localPath
        self.totalBytes = totalBytes
        self.transferredBytes = 0
        self.status = .queued
        self.errorMessage = nil
        self.createdAt = Date()
        self.finishedAt = nil
    }

    var isActive: Bool { status == .queued || status == .running }

    var progress: Double {
        guard totalBytes > 0 else { return status == .completed ? 1 : 0 }
        return min(1, Double(transferredBytes) / Double(totalBytes))
    }

    var statusText: String {
        switch status {
        case .queued: return "等待中"
        case .running: return "传输中 \(Int(progress * 100))%"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }
}
