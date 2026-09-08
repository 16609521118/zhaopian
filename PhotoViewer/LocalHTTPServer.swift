//
//  LocalHTTPServer.swift
//  PhotoViewer
//
//  极简版本地回环 HTTP 服务（仅监听 127.0.0.1）：
//    GET /              → 打包的 index.html
//    GET /api/folders   → 扫描 App Documents 目录，返回文件夹与媒体元数据 JSON
//    GET /media/<id>/<rel> → Documents 下的媒体文件（支持 Range，视频可拖动）
//    GET /icons/* 等    → 打包的静态资源
//
//  设计要点：不使用 UIDocumentPickerViewController（iOS 26 上文件夹选择器存在
//  "打开按钮无响应/置灰"的系统缺陷），改为让用户通过系统"文件"App 把照片
//  放进本 App 的 Documents 目录（开启 UIFileSharingEnabled 后在
//  "我的 iPhone > 照片查看器"中可见），App 直接扫描展示。
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

    /// App 沙盒 Documents 目录——用户通过"文件"App 在此放置照片/文件夹
    static var mediaRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true, attributes: nil)
        return docs
    }

    static func isFile(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
    }

    // MARK: - 启动

    func start() {
        guard listener == nil else { return }
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

        if segments.isEmpty {
            serveBundle(segments: ["index.html"], rangeHeader: nil, on: connection)
            return
        }

        switch segments[0] {
        case "api":
            if segments.count == 2, segments[1] == "folders" {
                sendFoldersJSON(on: connection)
            } else {
                sendText(connection: connection, status: 404, text: "Not found")
            }
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
            guard let fileURL = Self.resolveMediaFile(folderId: folderId, rel: rel) else {
                sendText(connection: connection, status: 404, text: "Not found")
                return
            }
            sendFile(connection: connection, url: fileURL, rangeHeader: rangeHeader)
        default:
            serveBundle(segments: segments, rangeHeader: rangeHeader, on: connection)
        }
    }

    // MARK: - 文件夹扫描 API

    /// 扫描 Documents 目录，返回 JSON：[{id, name, items:[{id,name,path,type,size}]}]
    /// 根目录下的媒体文件归入 id="root"、name="根目录"；每个子文件夹为一个条目。
    private func sendFoldersJSON(on connection: NWConnection) {
        let root = Self.mediaRoot
        let fm = FileManager.default
        var folders: [[String: Any]] = []

        // 根目录下的媒体文件
        let rootItems = Self.enumerateMedia(in: root, relativePrefix: "")
        if !rootItems.isEmpty {
            folders.append(["id": "root", "name": "根目录", "items": rootItems])
        }

        // 子文件夹（跳过系统/隐藏目录）
        let skipNames = Set(["thumbs", "Imported", "Mounted", ".Trash"])
        if let subdirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for dir in subdirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard !skipNames.contains(dir.lastPathComponent) else { continue }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
                let items = Self.enumerateMedia(in: dir, relativePrefix: "")
                // 空文件夹也展示（方便用户知道目录存在）
                folders.append(["id": dir.lastPathComponent, "name": dir.lastPathComponent, "items": items])
            }
        }

        let payload: [String: Any] = ["folders": folders]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else {
            sendText(connection: connection, status: 500, text: "JSON encode failed")
            return
        }
        sendData(connection: connection, data: data, contentType: "application/json; charset=utf-8")
    }

    /// 递归枚举目录中的媒体文件，返回条目数组
    private static func enumerateMedia(in folder: URL, relativePrefix: String) -> [[String: Any]] {
        let fm = FileManager.default
        var items: [[String: Any]] = []
        guard let enumerator = fm.enumerator(at: folder,
                                             includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                             options: [.skipsHiddenFiles]) else {
            return items
        }
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            let filename = fileURL.lastPathComponent
            guard isMediaFile(filename) else { continue }
            let rel = relativePrefix.isEmpty ? filename : "\(relativePrefix)/\(filename)"
            items.append([
                "id": rel,
                "name": filename,
                "path": rel,
                "type": isVideoFile(filename) ? "video" : "image",
                "size": values.fileSize ?? 0
            ])
        }
        return items
    }

    private static func isMediaFile(_ name: String) -> Bool {
        let exts = ["jpg","jpeg","png","gif","webp","bmp","heic","heif","mp4","mov","m4v","3gp"]
        return exts.contains((name as NSString).pathExtension.lowercased())
    }

    private static func isVideoFile(_ name: String) -> Bool {
        let exts = ["mp4","mov","m4v","3gp"]
        return exts.contains((name as NSString).pathExtension.lowercased())
    }

    // MARK: - 媒体文件解析

    /// folderId="root" → Documents/<rel>；否则 → Documents/<folderId>/<rel>
    static func resolveMediaFile(folderId: String, rel: String) -> URL? {
        guard !folderId.contains(".."), !rel.contains("..") else { return nil }
        let base = folderId == "root" ? mediaRoot : mediaRoot.appendingPathComponent(folderId, isDirectory: true)
        let url = base.appendingPathComponent(rel)
        return isFile(url) ? url : nil
    }

    // MARK: - 静态资源（打包进 App 的 web/）

    private func serveBundle(segments: [String], rangeHeader: String?, on connection: NWConnection) {
        guard let url = Self.bundleFileURL(segments: segments) else {
            sendText(connection: connection, status: 404, text: "Not found")
            return
        }
        sendFile(connection: connection, url: url, rangeHeader: rangeHeader)
    }

    private static func bundleFileURL(segments: [String]) -> URL? {
        guard let root = Bundle.main.url(forResource: "web", withExtension: nil) else { return nil }
        var url = root
        for seg in segments {
            url = url.appendingPathComponent(seg)
        }
        return isFile(url) ? url : nil
    }

    // MARK: - 响应发送

    private func sendText(connection: NWConnection, status: Int, text: String) {
        let data = Data(text.utf8)
        sendData(connection: connection, data: data, contentType: "text/plain; charset=utf-8", status: status)
    }

    private func sendData(connection: NWConnection, data: Data, contentType: String, status: Int = 200) {
        var head = "HTTP/1.1 \(status) \(Self.reasonPhrase(status))\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(data.count)\r\n"
        head += "Connection: close\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "\r\n"
        connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in
            connection.send(content: data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        })
    }

    private func sendFile(connection: NWConnection, url: URL, rangeHeader: String?) {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let fileSize = (attrs[.size] as? NSNumber)?.intValue, fileSize > 0 else {
            sendText(connection: connection, status: 404, text: "Not found")
            return
        }

        let mime = Self.mimeType(for: url)
        var start = 0
        var end = fileSize - 1
        var isPartial = false

        if let range = Self.parseRange(rangeHeader, fileSize: fileSize) {
            start = range.start
            end = range.end
            isPartial = true
        }
        let length = end - start + 1

        var head = "HTTP/1.1 \(isPartial ? 206 : 200) \(Self.reasonPhrase(isPartial ? 206 : 200))\r\n"
        head += "Content-Type: \(mime)\r\n"
        head += "Content-Length: \(length)\r\n"
        head += "Accept-Ranges: bytes\r\n"
        if isPartial {
            head += "Content-Range: bytes \(start)-\(end)/\(fileSize)\r\n"
        }
        head += "Connection: close\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "\r\n"

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            sendText(connection: connection, status: 500, text: "Cannot open file")
            return
        }
        if start > 0 { try? handle.seek(toOffset: UInt64(start)) }

        connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in
            Self.streamFile(connection: connection, handle: handle, remaining: length)
        })
    }

    private static func streamFile(connection: NWConnection, handle: FileHandle, remaining: Int) {
        guard remaining > 0 else {
            try? handle.close()
            connection.cancel()
            return
        }
        let chunkSize = min(64 * 1024, remaining)
        let data = handle.readData(ofLength: chunkSize)
        guard !data.isEmpty else {
            try? handle.close()
            connection.cancel()
            return
        }
        connection.send(content: data, completion: .contentProcessed { _ in
            streamFile(connection: connection, handle: handle, remaining: remaining - data.count)
        })
    }

    // MARK: - 工具

    private static func parseRange(_ header: String?, fileSize: Int) -> (start: Int, end: Int)? {
        guard let header = header, header.hasPrefix("bytes=") else { return nil }
        let spec = String(header.dropFirst("bytes=".count))
        let parts = spec.split(separator: "-")
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty {
            // suffix: bytes=-500
            guard let len = Int(parts[1]) else { return nil }
            let start = max(0, fileSize - len)
            return (start, fileSize - 1)
        }
        guard let start = Int(parts[0]) else { return nil }
        let end = parts[1].isEmpty ? fileSize - 1 : (Int(parts[1]) ?? fileSize - 1)
        guard start >= 0, start < fileSize, end >= start else { return nil }
        return (start, min(end, fileSize - 1))
    }

    private static func mimeType(for url: URL) -> String {
        if let ext = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType {
            return ext
        }
        return "application/octet-stream"
    }

    private static func reasonPhrase(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 206: return "Partial Content"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 431: return "Request Header Fields Too Large"
        case 500: return "Internal Server Error"
        default: return "OK"
        }
    }
}
