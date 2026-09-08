import Foundation

/// WebDAV 协议实现（基于 URLSession）。
/// 支持群晖 WebDAV、Nextcloud、坚果云、自建 nginx/lighttpd WebDAV 等。
final class WebDAVService: NSObject, RemoteFileSystem {
    private let mount: Mount
    private let password: String?
    private var session: URLSession!
    /// taskIdentifier -> 进度回调
    private var progressCallbacks: [Int: (Int64, Int64) -> Void] = [:]
    /// taskIdentifier -> 下载目标 URL
    private var downloadDestinations: [Int: URL] = [:]

    init(mount: Mount, password: String?) {
        self.mount = mount
        self.password = password
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    // MARK: - URL building

    private var rootURL: URL? {
        var comps = URLComponents()
        comps.scheme = "http"
        comps.host = mount.host
        comps.port = mount.port
        var path = mount.path
        if !path.hasPrefix("/") { path = "/" + path }
        if path.hasSuffix("/") { path = String(path.dropLast()) }
        comps.percentEncodedPath = path
        return comps.url
    }

    private func url(forPath path: String) throws -> URL {
        guard let root = rootURL else { throw MountError.invalidURL }
        var p = path
        if !p.hasPrefix("/") { p = "/" + p }
        // 编码每一段，保留 /
        let encoded = p.split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        let full = (root.absoluteString + encoded)
            .replacingOccurrences(of: "//", with: "/")
            .replacingOccurrences(of: "http:/", with: "http://")
        guard let url = URL(string: full) else { throw MountError.invalidURL }
        return url
    }

    private var authHeader: [String: String] {
        guard !mount.isAnonymous else { return [:] }
        let cred = "\(mount.username):\(password ?? "")"
        let base64 = Data(cred.utf8).base64EncodedString()
        return ["Authorization": "Basic \(base64)"]
    }

    // MARK: - RemoteFileSystem

    func connect() async throws {
        // WebDAV 无持久连接概念；用一次 PROPFIND 验证可达性与凭据
        _ = try await listDirectory(at: "/")
    }

    func disconnect() {}

    func listDirectory(at path: String) async throws -> [RemoteItem] {
        let url = try url(forPath: path)
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        for (k, v) in authHeader { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = Data(
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
            + "<D:propfind xmlns:D=\"DAV:\"><D:prop>"
            + "<D:resourcetype/><D:getcontentlength/><D:getlastmodified/>"
            + "</D:prop></D:propfind>".utf8)

        let (data, response) = try await session.data(for: request)
        try validate(response, url: url)
        guard let data = data as Data? else { return [] }
        return try WebDAVXMLParser.parse(data, basePath: path)
    }

    func download(path: String, to localURL: URL,
                  progress: @escaping (Int64, Int64) -> Void) async throws {
        let url = try url(forPath: path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (k, v) in authHeader { request.setValue(v, forHTTPHeaderField: k) }

        let task = session.downloadTask(with: request)
        progressCallbacks[task.taskIdentifier] = progress
        downloadDestinations[task.taskIdentifier] = localURL

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingDownloads[task.taskIdentifier] = continuation
            task.resume()
        }
    }

    func upload(from localURL: URL, to path: String,
                progress: @escaping (Int64, Int64) -> Void) async throws {
        let url = try url(forPath: path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        for (k, v) in authHeader { request.setValue(v, forHTTPHeaderField: k) }

        let task = session.uploadTask(with: request, fromFile: localURL)
        progressCallbacks[task.taskIdentifier] = progress

        let result: (Data?, URLResponse) = try await withCheckedThrowingContinuation { continuation in
            pendingUploads[task.taskIdentifier] = continuation
            task.resume()
        }
        try validate(result.1, url: url)
    }

    func createDirectory(at path: String) async throws {
        let url = try url(forPath: path)
        var request = URLRequest(url: url)
        request.httpMethod = "MKCOL"
        for (k, v) in authHeader { request.setValue(v, forHTTPHeaderField: k) }
        let (_, response) = try await session.data(for: request)
        try validate(response, url: url)
    }

    func deleteItem(at path: String, isDirectory: Bool) async throws {
        let url = try url(forPath: path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if isDirectory { request.setValue("infinity", forHTTPHeaderField: "Depth") }
        for (k, v) in authHeader { request.setValue(v, forHTTPHeaderField: k) }
        let (_, response) = try await session.data(for: request)
        try validate(response, url: url)
    }

    func renameItem(at path: String, to newName: String) async throws {
        let parent = RemoteItem.parent(of: path)
        let newPath = RemoteItem.join(parent, newName)
        try await moveItem(from: path, to: newPath)
    }

    func moveItem(from path: String, to newPath: String) async throws {
        let src = try url(forPath: path)
        let dst = try url(forPath: newPath)
        var request = URLRequest(url: src)
        request.httpMethod = "MOVE"
        request.setValue(dst.absoluteString, forHTTPHeaderField: "Destination")
        request.setValue("F", forHTTPHeaderField: "Overwrite")
        for (k, v) in authHeader { request.setValue(v, forHTTPHeaderField: k) }
        let (_, response) = try await session.data(for: request)
        try validate(response, url: src)
    }

    // MARK: - Download continuation plumbing

    private var pendingDownloads: [Int: CheckedContinuation<Void, Error>] = [:]
    private var pendingUploads: [Int: CheckedContinuation<(Data?, URLResponse), Error>] = [:]

    private func validate(_ response: URLResponse?, url: URL) throws {
        guard let http = response as? HTTPURLResponse else {
            throw MountError.connectionFailed("无效响应")
        }
        switch http.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw MountError.authenticationFailed
        case 404:
            throw MountError.notFound(url.lastPathComponent)
        default:
            throw MountError.serverError(http.statusCode, HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
    }
}

// MARK: - URLSession delegate

extension WebDAVService: URLSessionTaskDelegate, URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskIdentifier
        if let cb = progressCallbacks[id] {
            cb(totalBytesWritten, totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        let id = task.taskIdentifier
        if let cb = progressCallbacks[id] {
            cb(totalBytesSent, totalBytesExpectedToSend)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let id = downloadTask.taskIdentifier
        guard let continuation = pendingDownloads.removeValue(forKey: id),
              let destination = downloadDestinations.removeValue(forKey: id) else { return }
        progressCallbacks.removeValue(forKey: id)
        do {
            if let response = downloadTask.response as? HTTPURLResponse, response.statusCode != 200 {
                throw MountError.serverError(response.statusCode, HTTPURLResponse.localizedString(forStatusCode: response.statusCode))
            }
            let fm = FileManager.default
            try? fm.removeItem(at: destination)
            try fm.moveItem(at: location, to: destination)
            continuation.resume()
        } catch {
            continuation.resume(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        if let continuation = pendingDownloads.removeValue(forKey: id) {
            progressCallbacks.removeValue(forKey: id)
            downloadDestinations.removeValue(forKey: id)
            if let error {
                continuation.resume(throwing: self.mapError(error))
            } else if let http = task.response as? HTTPURLResponse, http.statusCode != 200 {
                continuation.resume(throwing: MountError.serverError(http.statusCode, HTTPURLResponse.localizedString(forStatusCode: http.statusCode)))
            } else if task.response == nil {
                continuation.resume(throwing: MountError.unknown("下载未完成"))
            }
            // 正常下载完成时由 didFinishDownloadingTo 恢复 continuation
        }
        if let continuation = pendingUploads.removeValue(forKey: id) {
            progressCallbacks.removeValue(forKey: id)
            if let error {
                continuation.resume(throwing: self.mapError(error))
            } else {
                continuation.resume(returning: (nil, task.response!))
            }
        }
    }

    private func mapError(_ error: Error) -> Error {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCancelled:
                return MountError.cancelled
            case NSURLErrorTimedOut:
                return MountError.connectionFailed("连接超时")
            case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
                return MountError.connectionFailed("无法连接服务器，请检查 IP / 端口")
            default:
                return MountError.connectionFailed(ns.localizedDescription)
            }
        }
        return MountError.connectionFailed(error.localizedDescription)
    }
}

// MARK: - PROPFIND response parser

/// 解析 WebDAV PROPFIND 的 multistatus XML，忽略命名空间前缀。
private final class WebDAVXMLParser: NSObject, XMLParserDelegate {
    private var items: [RemoteItem] = []
    private var currentHref: String?
    private var currentIsCollection = false
    private var currentSize: Int64?
    private var currentModified: Date?
    private var currentText = ""
    private var depthInResponse = 0
    private var inResponse = false
    private var inPropstat = false

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    static func parse(_ data: Data, basePath: String) throws -> [RemoteItem] {
        let parser = WebDAVXMLParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else {
            throw MountError.unknown("解析服务器目录信息失败")
        }
        return RemoteItem.sorted(parser.items)
    }

    private func localName(_ elementName: String) -> String {
        if let colon = elementName.firstIndex(of: ":") {
            return String(elementName[elementName.index(after: colon)...])
        }
        return elementName
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let name = localName(elementName)
        currentText = ""
        switch name {
        case "response":
            inResponse = true
            depthInResponse = 1
            currentHref = nil
            currentIsCollection = false
            currentSize = nil
            currentModified = nil
        case "propstat":
            inPropstat = true
        case "collection":
            if inResponse { currentIsCollection = true }
        default:
            break
        }
        if inResponse, name != "response" { depthInResponse += 1 }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let name = localName(elementName)
        switch name {
        case "href":
            if inResponse {
                currentHref = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case "getcontentlength":
            currentSize = Int64(currentText.trimmingCharacters(in: .whitespacesAndNewlines))
        case "getlastmodified":
            let t = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            currentModified = dateFormatter.date(from: t)
        case "propstat":
            inPropstat = false
        case "response":
            if inResponse, let href = currentHref, let decoded = href.removingPercentEncoding {
                // 跳过条目自身（href == 请求路径）
                let pathPart = decoded.components(separatedBy: "://").last ?? decoded
                let last = RemoteItem.name(of: pathPart)
                let base = RemoteItem.name(of: basePath)
                if last != base, !last.isEmpty {
                    let itemPath = RemoteItem.join(basePath, last)
                    items.append(RemoteItem(
                        name: last,
                        path: itemPath,
                        type: currentIsCollection ? .directory : .file,
                        size: currentIsCollection ? nil : currentSize,
                        modifiedAt: currentModified
                    ))
                }
            }
            inResponse = false
        default:
            break
        }
        if inResponse, name != "response", depthInResponse > 1 {
            depthInResponse -= 1
        }
    }
}
