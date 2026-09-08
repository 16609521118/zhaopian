import Foundation
import Combine

/// 传输队列：串行执行下载 / 上传，跟踪进度与历史。
@MainActor
final class TransferViewModel: ObservableObject {
    @Published private(set) var tasks: [TransferTask] = []

    private var activeTaskID: UUID?
    private var pendingService: RemoteFileSystem?

    var activeTasks: [TransferTask] { tasks.filter(\.isActive) }
    var history: [TransferTask] { tasks.filter { !$0.isActive }.reversed() }

    init() {
        loadHistory()
    }

    /// 入队并启动（若当前无活动任务）
    func enqueue(_ task: TransferTask, using service: RemoteFileSystem) {
        tasks.append(task)
        pendingService = service
        saveHistory()
        runNext()
    }

    func cancel(_ task: TransferTask) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx].status = .cancelled
        tasks[idx].finishedAt = Date()
        // AMSMB2 / URLSession 不支持按任务取消，简单标记为取消
        saveHistory()
    }

    func remove(_ task: TransferTask) {
        tasks.removeAll { $0.id == task.id }
        saveHistory()
    }

    func clearHistory() {
        tasks.removeAll { !$0.isActive }
        saveHistory()
    }

    // MARK: - Runner

    private func runNext() {
        guard activeTaskID == nil,
              let idx = tasks.firstIndex(where: { $0.status == .queued }) else { return }
        guard let service = pendingService else { return }
        activeTaskID = tasks[idx].id
        tasks[idx].status = .running
        let task = tasks[idx]

        Task {
            do {
                try await execute(task, service: service) { [weak self] transferred, total in
                    Task { @MainActor in
                        guard let self, let i = self.tasks.firstIndex(where: { $0.id == task.id }) else { return }
                        if total > 0 { self.tasks[i].totalBytes = total }
                        self.tasks[i].transferredBytes = transferred
                    }
                }
                if let i = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[i].status = .completed
                    tasks[i].finishedAt = Date()
                }
            } catch {
                if let i = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[i].status = .failed
                    tasks[i].errorMessage = error.localizedDescription
                    tasks[i].finishedAt = Date()
                }
            }
            activeTaskID = nil
            saveHistory()
            runNext()
        }
    }

    private func execute(_ task: TransferTask, service: RemoteFileSystem,
                         progress: @escaping (Int64, Int64) -> Void) async throws {
        switch task.direction {
        case .download:
            let localURL = URL(fileURLWithPath: task.localPath)
            try await service.download(path: task.remotePath, to: localURL, progress: progress)
        case .upload:
            let localURL = URL(fileURLWithPath: task.localPath)
            try await service.upload(from: localURL, to: task.remotePath, progress: progress)
        }
    }

    // MARK: - Persistence (history only)

    private var historyURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("transfers.json")
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([TransferTask].self, from: data) {
            // 只恢复已完成/失败/取消的历史
            tasks = decoded.filter { !$0.isActive }
        }
    }

    private func saveHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(tasks.filter { !$0.isActive }) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }
}
