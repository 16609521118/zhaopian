//
//  LocalHTTPServer.swift
//  PhotoViewer
//
//  本地回环 HTTP 服务（仅监听 127.0.0.1）：为 WKWebView 提供网页与媒体文件。
//  iOS 26 上自定义 URL Scheme 的 WKURLSchemeHandler + HTML5 媒体存在兼容问题
//  （媒体元素加载本地/自定义 scheme 文件失败、自定义 scheme 页面含脚本会终止 WebKit），
//  因此改为标准 HTTP 回环服务提供资源，视频播放改用原生 AVPlayer（见 ViewController）。
//
//  能力：仅 GET；支持 Range（视频拖动）；媒体解析顺序：
//    1. 书签挂载目录（原位访问，不复制）
//    2. 旧版复制目录 Documents/Mounted（兼容 v2 已挂载数据）
//    3. 导入目录 Documents/Imported（导入到 App 的文件）
//

import Foundation
import Network
import UniformTypeIdentifiers

final class LocalHTTPServer {

    static let shared = LocalHTTPServer()

    private(set) var port: UInt16 = 0
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "photoviewer.http.server")

    var baseURL: URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }

    // MARK: - 目录

    /// 旧版（v2）复制式挂载根目录：Documents/Mounted，仅用于兼容旧数据
    static var legacyMountedRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Mounted", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }

    /// 导入文件目录：Documents/Imported/<folderId>/...
    static var importedRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Imported", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }

    /// 原生缩略图目录：Documents/thumbs（每次启动清空，由网页按需重新生成）
    static var thumbsRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }

    static func isFile(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
    }

    // MARK: - 启动

    func start() {
        guard listener == nil else { return }
        // 从 8765 起尝试固定端口，避免与其它本地服务冲突；端口变化不影响网页（网页每次向原生查询 base）
        for p in 8765...8780 {
            do {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                params.requiredLocalEndpoint = NWEndpoint.hostPort(
                    host: "127.0.0.1",
                    port: NWEndpoint.Port(rawValue: UInt16(p))!
                )
                let listener = try NWListener(using: params)
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handleConnection(connection)
                }
                listener.stateUpdateHandler = { state in
                    if case .failed(let error) = state {
                        print("PhotoViewer HTTP listener failed: \(error.localizedDescription)")
                    }
                }
                listener.start(queue: queue)
                self.listener = listener
                port = UInt16(p)
                clearThumbnails()
                print("PhotoViewer HTTP server listening on 127.0.0.1:\(p)")
                return
            } catch {
                print("PhotoViewer HTTP port \(p) unavailable: \(error.localizedDescription)")
            }
        }
        print("PhotoViewer HTTP server failed to start on any port")
    }

    // MARK: - 请求处理

    private final class ConnectionBox {
        let connection: NWConnection
        var buffer = Data()
        init(_ connection: NWConnection) {
            self.connection = connection
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        pump(ConnectionBox(connection))
    }

    private func pump(_ box: ConnectionBox) {
        box.connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                box.connection.cancel()
                return
            }
            if let data = data, !data.isEmpty {
                box.buffer.append(data)
                if let range = box.buffer.range(of: Data("\r\n\r\n".utf8)) {
                    let headerData = box.buffer.subdata(in: 0..<range.lowerBound)
                    self.dispatchRequest(headerData, on: box.connection)
                    return
                }
                if box.buffer.count > 64 * 1024 {
                    self.sendText(connection: box.connection, status: 431, text: "Request header too large")
                    return
                }
            }
            if isComplete || error != nil {
                box.connection.cancel()
                return
            }
            self.pump(box)
        }
    }

    private func dispatchRequest(_ headerData: Data, on connection: NWConnection) {
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            sendText(connection: connection, status: 400, text: "Bad request")
            return
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendText(connection: connection, status: 400, text: "Bad request")
            return
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            sendText(connection: connection, status: 405, text: "Method not allowed")
            return
        }
        let rawPath = String(parts[1])
        var rangeHeader: String?
        for line in lines.dropFirst() {
            if line.lowercased().hasPrefix("range:") {
                rangeHeader = line.dropFirst("range:".count).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        handleGET(rawPath: rawPath, rangeHeader: rangeHeader, on: connection)
    }

    private func handleGET(rawPath: String, rangeHeader: String?, on connection: NWConnection) {
        guard let url = URL(string: rawPath) else {
            sendText(connection: connection, status: 400, text: "Bad request")
            return
        }
        let segments = url.path.split(separator: "/").map {
            String($0).removingPercentEncoding ?? String($0)
        }
        guard segments.allSatisfy({ !$0.isEmpty && $0 != ".." && !$0.contains("/") }) else {
            sendText(connection: connection, status: 404, text: "Not found")
            return
        }
        guard !segments.isEmpty else {
            // "/" → index.html
            serveBundle(segments: ["index.html"], rangeHeader: nil, on: connection)
            return
        }

        switch segments[0] {
        case "media":
            guard segments.count >= 3 else {
                sendText(connection: connection, status: 404, text: "Not found")
                return
            }
            let folderId = segments[1]
            let rel = segments.dropFirst(2).joined(separator: "/")
            guard !folderId.isEmpty, !rel.isEmpty else {
                sendText(connection: connection, status: 404, text: "Not found")
                return
            }
            guard let (fileURL, cleanup) = Self.resolveMediaFile(folderId: folderId, rel: rel) else {
                sendText(connection: connection, status: 404, text: "Not found")
                return
            }
            sendFile(connection: connection, url: fileURL, rangeHeader: rangeHeader, cleanup: cleanup)
        case "thumbs":
            guard segments.count == 2 else {
                sendText(connection: connection, status: 404, text: "Not found")
                return
            }
            let fileURL = Self.thumbsRoot.appendingPathComponent(segments[1])
            guard Self.isFile(fileURL) else {
                sendText(connection: connection, status: 404, text: "Not found")
                return
            }
            sendFile(connection: connection, url: fileURL, rangeHeader: rangeHeader, cleanup: {})
        default:
            serveBundle(segments: segments, rangeHeader: rangeHeader, on: connection)
        }
    }

    // MARK: - 资源解析

    /// 解析 /media/<folderId>/<rel> 对应的本地文件，返回 (URL, 清理闭包)。
    /// 书签目录访问期间持有安全作用域，读取完成后必须执行清理闭包释放。
    static func resolveMediaFile(folderId: String, rel: String) -> (url: URL, cleanup: () -> Void)? {
        // 1) 书签挂载目录（原位访问，不复制）
        if let base = MountedFolderStore.shared.resolve(folderId) {
            let accessing = base.startAccessingSecurityScopedResource()
            let candidate = base.appendingPathComponent(rel)
            if isFile(candidate) {
                return (candidate, {
                    if accessing {
                        base.stopAccessingSecurityScopedResource()
                    }
                })
            }
            if accessing {
                base.stopAccessingSecurityScopedResource()
            }
        }
        // 2) 旧版复制目录（兼容 v2 已挂载的文件夹）
        let legacy = legacyMountedRoot.appendingPathComponent(folderId).appendingPathComponent(rel)
        if isFile(legacy) {
            return (legacy, {})
        }
        // 3) 导入文件目录
        let imported = importedRoot.appendingPathComponent(folderId).appendingPathComponent(rel)
        if isFile(imported) {
            return (imported, {})
        }
        return nil
    }

    private func serveBundle(segments: [String], rangeHeader: String?, on connection: NWConnection) {
        guard let fileURL = bundleFileURL(segments) else {
            sendText(connection: connection, status: 404, text: "Not found")
            return
        }
        sendFile(connection: connection, url: fileURL, rangeHeader: rangeHeader, cleanup: {})
    }

    private func bundleFileURL(_ segments: [String]) -> URL? {
        let fm = FileManager.default
        var base: URL? = Bundle.main.resourceURL?.appendingPathComponent("web", isDirectory: true)
        if let b = base, !fm.fileExists(atPath: b.path) {
            base = Bundle.main.resourceURL
        }
        guard let root = base else { return nil }
        var url = root
        for seg in segments {
            url = url.appendingPathComponent(seg)
        }
        return isFile(url) ? url : nil
    }

    // MARK: - 响应

    private func sendText(connection: NWConnection, status: Int, text: String) {
        sendResponse(connection: connection,
                     status: status,
                     headers: ["Content-Type": "text/plain; charset=utf-8"],
                     body: Data(text.utf8))
    }

    private func sendResponse(connection: NWConnection, status: Int, headers: [String: String], body: Data) {
        var head = "HTTP/1.1 \(status) \(Self.reasonPhrase(status))\r\n"
        for (key, value) in headers {
            head += "\(key): \(value)\r\n"
        }
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var payload = Data(head.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendFile(connection: NWConnection, url: URL, rangeHeader: String?, cleanup: @escaping () -> Void) {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let sizeNumber = attrs[.size] as? NSNumber else {
            cleanup()
            sendText(connection: connection, status: 404, text: "Not found")
            return
        }
        let fileSize = sizeNumber.intValue

        var status = 200
        var start = 0
        var end = fileSize - 1
        if let range = Self.parseRange(rangeHeader, fileSize: fileSize) {
            status = 206
            start = range.start
            end = range.end
        }

        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"

        guard fileSize > 0 else {
            var head = "HTTP/1.1 200 OK\r\nContent-Type: \(mime)\r\n"
            head += "Content-Length: 0\r\nAccept-Ranges: bytes\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in
                cleanup()
                connection.cancel()
            })
            return
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            cleanup()
            sendText(connection: connection, status: 500, text: "Cannot open file")
            return
        }
        try? handle.seek(toOffset: UInt64(start))
        let length = end - start + 1

        var head = "HTTP/1.1 \(status) \(Self.reasonPhrase(status))\r\n"
        head += "Content-Type: \(mime)\r\n"
        head += "Accept-Ranges: bytes\r\n"
        head += "Cache-Control: no-cache\r\n"
        head += "Connection: close\r\n"
        if status == 206 {
            head += "Content-Range: bytes \(start)-\(end)/\(fileSize)\r\n"
        }
        head += "Content-Length: \(length)\r\n\r\n"

        connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in
            self.streamFile(handle: handle, remaining: length, connection: connection, cleanup: cleanup)
        })
    }

    private func streamFile(handle: FileHandle, remaining: Int, connection: NWConnection, cleanup: @escaping () -> Void) {
        if remaining <= 0 {
            try? handle.close()
            cleanup()
            connection.cancel()
            return
        }
        let chunk = min(64 * 1024, remaining)
        let data = handle.readData(ofLength: chunk)
        if data.isEmpty {
            try? handle.close()
            cleanup()
            connection.cancel()
            return
        }
        connection.send(content: data, completion: .contentProcessed { _ in
            self.streamFile(handle: handle, remaining: remaining - data.count, connection: connection, cleanup: cleanup)
        })
    }

    // MARK: - 工具

    private func clearThumbnails() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: Self.thumbsRoot, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension.lowercased() == "jpg" {
            try? fm.removeItem(at: file)
        }
    }

    static func parseRange(_ header: String?, fileSize: Int) -> (start: Int, end: Int)? {
        guard let header = header, header.hasPrefix("bytes="), fileSize > 0 else { return nil }
        let spec = header.dropFirst("bytes=".count)
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first, !first.isEmpty, let start = Int(first), start >= 0, start < fileSize else {
            return nil
        }
        if parts.count == 1 || (parts.count > 1 && parts[1].isEmpty) {
            return (start, fileSize - 1)
        }
        guard let end = Int(parts[1]), end >= start else { return nil }
        return (start, min(end, fileSize - 1))
    }

    static func reasonPhrase(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 206: return "Partial Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 431: return "Request Header Fields Too Large"
        default: return "Server Error"
        }
    }
}
