//
//  LocalFileSchemeHandler.swift
//  PhotoViewer
//
//  自定义 URL Scheme：localapp://media/<folderId>/<encoded相对路径>
//  映射到 App 沙盒 Documents/Mounted/ 下的本地文件，实现完全离线访问。
//  支持 HTTP Range 请求（视频拖动播放必需），并允许网页内跨源读取（canvas 视频缩略图）。
//

import Foundation
import WebKit
import UniformTypeIdentifiers

class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {

    static let scheme = "localapp"

    private let lock = NSLock()
    private var activeTasks: [Int: WKURLSchemeTask] = [:]

    /// 挂载文件的根目录（Documents/Mounted/）
    static var mountedRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Mounted", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }

    // MARK: - WKURLSchemeHandler

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        lock.lock()
        activeTasks[task.hash] = task
        lock.unlock()

        guard let url = task.request.url else {
            fail(task, code: .badURL)
            return
        }

        let prefix = "/media/"
        let path = url.path
        guard path.hasPrefix(prefix) else {
            fail(task, code: .fileDoesNotExist)
            return
        }

        let relative = String(path.dropFirst(prefix.count)).removingPercentEncoding ?? ""
        guard !relative.isEmpty,
              !relative.contains(".."),
              !relative.hasPrefix("/") else {
            fail(task, code: .fileDoesNotExist)
            return
        }

        let fileURL = Self.mountedRoot.appendingPathComponent(relative)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue else {
            fail(task, code: .fileDoesNotExist)
            return
        }

        // 在后台线程做 IO，避免阻塞 WebKit 请求线程
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
                  let fileSize = (attrs[.size] as? NSNumber)?.intValue, fileSize >= 0 else {
                self.fail(task, code: .cannotOpenFile)
                return
            }

            let rangeHeader = task.request.value(forHTTPHeaderField: "Range")
            var data: Data
            var statusCode = 200
            var contentRange: String?

            if let range = Self.parseRange(rangeHeader, fileSize: fileSize) {
                guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
                    self.fail(task, code: .cannotOpenFile)
                    return
                }
                defer { try? handle.close() }
                try? handle.seek(toOffset: UInt64(range.start))
                let length = range.end - range.start + 1
                data = handle.readData(ofLength: length)
                statusCode = 206
                contentRange = "bytes \(range.start)-\(range.end)/\(fileSize)"
            } else {
                guard let d = try? Data(contentsOf: fileURL) else {
                    self.fail(task, code: .cannotOpenFile)
                    return
                }
                data = d
            }

            let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"

            var headers: [String: String] = [
                "Content-Type": mime,
                "Accept-Ranges": "bytes",
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "no-cache"
            ]
            if let cr = contentRange {
                headers["Content-Range"] = cr
            }

            let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!

            DispatchQueue.main.async {
                guard let task = self.takeTask(task) else { return }
                task.didReceive(response)
                task.didReceive(data)
                task.didFinish()
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        lock.lock()
        activeTasks.removeValue(forKey: task.hash)
        lock.unlock()
    }

    // MARK: - 私有

    private func takeTask(_ task: WKURLSchemeTask) -> WKURLSchemeTask? {
        lock.lock()
        defer { lock.unlock() }
        return activeTasks.removeValue(forKey: task.hash)
    }

    private func fail(_ task: WKURLSchemeTask, code: URLError.Code) {
        DispatchQueue.main.async {
            guard let task = self.takeTask(task) else { return }
            task.didFailWithError(URLError(code))
        }
    }

    private static func parseRange(_ header: String?, fileSize: Int) -> (start: Int, end: Int)? {
        guard let header = header, header.hasPrefix("bytes="), fileSize > 0 else { return nil }
        let parts = header.dropFirst("bytes=".count).split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first, let start = Int(first) else { return nil }
        var end = fileSize - 1
        if parts.count > 1, let e = Int(parts[1]) {
            end = min(e, fileSize - 1)
        }
        guard start >= 0, start <= end else { return nil }
        return (start, end)
    }
}
