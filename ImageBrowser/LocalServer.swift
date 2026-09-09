import Foundation
import Network
import SwiftUI

// MARK: - 局域网 HTTP 服务（IP 映射）

/// 在 App 内启动一个局域网 HTTP 服务，将“我的图片”目录暴露给电脑浏览器：
/// - GET    浏览目录 / 下载文件
/// - PUT    上传文件（浏览器可用的 WebDAV 风格）
/// - DELETE 删除文件
/// 对应“127.0.0.1 / 局域网 IP 映射”的形态：服务运行在 App 沙盒内，指向 App 自己的文件夹。
final class LocalFileServer: ObservableObject {
    @Published var isRunning = false
    @Published var port: UInt16 = 8080
    @Published var localIPs: [String] = []

    let rootURL: URL
    let rootName: String

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "localserver")

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        rootURL = docs.appendingPathComponent("Images", isDirectory: true)
        rootName = "我的图片"
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        localIPs = Self.localIPAddresses()
    }

    /// 访问地址：127.0.0.1（本机回环）+ 各局域网 IP（电脑用）
    var accessURLs: [String] {
        var urls = ["http://127.0.0.1:\(port)/"]
        for ip in localIPs {
            urls.append("http://\(ip):\(port)/")
        }
        return urls
    }

    // MARK: - 启停

    func start() {
        guard listener == nil else { return }
        start(attempt: 0)
    }

    private func start(attempt: Int) {
        guard attempt < 30 else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            l.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            l.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    self?.stop()
                }
            }
            l.start(queue: queue)
            listener = l
            isRunning = true
        } catch {
            port &+= 1
            start(attempt: attempt + 1)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        isRunning = false
    }

    // MARK: - 连接处理

    private func handle(_ conn: NWConnection) {
        connections.append(conn)
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.drop(conn)
            default:
                break
            }
        }
        conn.start(queue: queue)
        readRequestHead(conn)
    }

    private func drop(_ conn: NWConnection) {
        connections.removeAll { $0 === conn }
    }

    /// 读取 HTTP 头（直到 \r\n\r\n）
    private func readRequestHead(_ conn: NWConnection, buffer: Data = Data()) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, error in
            guard let self = self else { return }
            var buf = buffer
            if let data = data {
                buf.append(data)
            }
            if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
                let headData = buf[..<range.upperBound]
                let body = buf[range.upperBound...]
                if let req = HTTPRequest(Data(headData)) {
                    self.dispatch(req, body: Data(body), conn: conn)
                } else {
                    self.respond(conn, status: 400, body: Data("Bad Request".utf8))
                }
                return
            }
            if error != nil {
                conn.cancel()
                return
            }
            self.readRequestHead(conn, buffer: buf)
        }
    }

    /// 补齐 body 至 Content-Length
    private func dispatch(_ req: HTTPRequest, body: Data, conn: NWConnection) {
        if body.count < req.contentLength {
            receiveBody(conn, req: req, accumulated: body) { [weak self] full in
                self?.process(req, body: full, conn: conn)
            }
        } else {
            process(req, body: body, conn: conn)
        }
    }

    private func receiveBody(_ conn: NWConnection, req: HTTPRequest, accumulated: Data, completion: @escaping (Data) -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, error in
            var acc = accumulated
            if let data = data {
                acc.append(data)
            }
            if acc.count >= req.contentLength {
                completion(Data(acc.prefix(req.contentLength)))
            } else if error != nil {
                completion(Data())
            } else {
                self.receiveBody(conn, req: req, accumulated: acc, completion: completion)
            }
        }
    }

    // MARK: - 路由

    private func process(_ req: HTTPRequest, body: Data, conn: NWConnection) {
        switch req.method.uppercased() {
        case "GET":
            handleGET(req.rawPath, conn: conn)
        case "PUT":
            handlePUT(req.rawPath, body: body, conn: conn)
        case "DELETE":
            handleDELETE(req.rawPath, conn: conn)
        case "OPTIONS":
            respond(conn, status: 200, body: Data(), contentType: "text/plain; charset=utf-8",
                    extraHeaders: "Allow: GET, PUT, DELETE, OPTIONS\r\n")
        default:
            respond(conn, status: 405, body: Data("Method Not Allowed".utf8))
        }
    }

    private func handleGET(_ path: String, conn: NWConnection) {
        let cleaned = path.removingPercentEncoding ?? path
        if cleaned == "/" || cleaned.isEmpty {
            respond(conn, status: 200, body: directoryHTML())
            return
        }
        guard let name = safeFileName(path), !name.isEmpty else {
            respond(conn, status: 400, body: Data("Bad Request".utf8))
            return
        }
        let url = rootURL.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else {
            respond(conn, status: 404, body: Data("Not Found".utf8))
            return
        }
        respond(conn, status: 200, body: data, contentType: contentType(for: url.pathExtension))
    }

    private func handlePUT(_ path: String, body: Data, conn: NWConnection) {
        guard let name = safeFileName(path), !name.isEmpty else {
            respond(conn, status: 400, body: Data("Bad Request".utf8))
            return
        }
        let dest = rootURL.appendingPathComponent(name)
        do {
            try body.write(to: dest)
            respond(conn, status: 201, body: Data("Created".utf8), contentType: "text/plain; charset=utf-8")
        } catch {
            respond(conn, status: 500, body: Data("Write failed".utf8))
        }
    }

    private func handleDELETE(_ path: String, conn: NWConnection) {
        guard let name = safeFileName(path), !name.isEmpty else {
            respond(conn, status: 400, body: Data("Bad Request".utf8))
            return
        }
        let url = rootURL.appendingPathComponent(name)
        do {
            try FileManager.default.removeItem(at: url)
            respond(conn, status: 200, body: Data("Deleted".utf8), contentType: "text/plain; charset=utf-8")
        } catch {
            respond(conn, status: 404, body: Data("Not Found".utf8))
        }
    }

    /// 只允许单层文件名（lastPathComponent），天然防路径穿越
    private func safeFileName(_ path: String) -> String? {
        guard let decoded = path.removingPercentEncoding else { return nil }
        let name = (decoded as NSString).lastPathComponent
        if name.isEmpty || name == "/" || name == "." || name == ".." {
            return nil
        }
        return name
    }

    // MARK: - 目录页

    private func directoryHTML() -> Data {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        var rows = ""
        for url in files.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let name = url.lastPathComponent
            let size = ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            let href = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
            rows += "<tr><td><a href=\"/\(Self.htmlEscape(href))\">\(Self.htmlEscape(name))</a></td><td>\(Self.formatBytes(size))</td></tr>"
        }
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>图览 · 我的图片</title>
        <style>
        body{font-family:-apple-system,system-ui,sans-serif;margin:40px auto;max-width:900px;padding:0 16px;color:#1c1c1e}
        h2{font-weight:600}
        p.sub{color:#8e8e93;font-size:14px}
        table{width:100%;border-collapse:collapse;margin-top:16px}
        th,td{text-align:left;padding:10px 8px;border-bottom:1px solid #e5e5ea;font-size:15px}
        th{color:#8e8e93;font-weight:500}
        td a{color:#0a84ff;text-decoration:none;word-break:break-all}
        .tip{background:#f2f2f7;border-radius:8px;padding:12px 16px;font-size:13px;color:#3a3a3c;margin-top:24px}
        </style>
        </head>
        <body>
        <h2>图览 · 我的图片</h2>
        <p class="sub">共 \(files.count) 个文件 · GET 下载 · PUT 上传 · DELETE 删除</p>
        <table>
        <tr><th>文件名</th><th>大小</th></tr>
        \(rows)
        </table>
        <div class="tip">上传文件：<code>curl -X PUT -T 本地文件 http://<本机IP>:\(port)/文件名</code><br>或在支持 WebDAV 的文件管理器中添加服务器地址。</div>
        </body>
        </html>
        """
        return Data(html.utf8)
    }

    // MARK: - 响应

    private func respond(_ conn: NWConnection, status: Int, body: Data,
                         contentType: String = "text/plain; charset=utf-8",
                         extraHeaders: String = "") {
        let reason = Self.statusText[status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += extraHeaders
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        conn.send(content: data, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private static let statusText: [Int: String] = [
        200: "OK", 201: "Created", 204: "No Content", 400: "Bad Request",
        404: "Not Found", 405: "Method Not Allowed", 500: "Internal Server Error"
    ]

    // MARK: - 工具

    private func contentType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic", "heif": return "image/heic"
        case "bmp": return "image/bmp"
        case "tiff": return "image/tiff"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "m4v": return "video/x-m4v"
        case "3gp": return "video/3gpp"
        case "txt", "md": return "text/plain; charset=utf-8"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }

    private static func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// 获取本机局域网 IPv4 地址（en0 / pdp_ip 开头接口，排除自愈地址）
    private static func localIPAddresses() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return [] }
        var ptr = ifaddr
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let addr = p.pointee.ifa_addr
            guard addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: p.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(addr.pointee.sa_len)
            if getnameinfo(addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host)
                if !ip.hasPrefix("169.254") && !addresses.contains(ip) {
                    addresses.append(ip)
                }
            }
        }
        freeifaddrs(ifaddr)
        return addresses
    }
}

/// 简易 HTTP 请求解析（首行 + Content-Length）
private struct HTTPRequest {
    let method: String
    let rawPath: String
    let contentLength: Int

    init?(_ headData: Data) {
        guard let text = String(data: headData, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        method = String(parts[0])
        rawPath = String(parts[1])
        var length = 0
        for line in lines.dropFirst() {
            if line.lowercased().hasPrefix("content-length:") {
                let value = line.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)
                length = Int(value) ?? 0
            }
        }
        contentLength = length
    }
}

// MARK: - 界面

/// 局域网映射界面：启动/停止服务，显示访问地址
struct LocalServerView: View {
    @StateObject private var server = LocalFileServer()

    var body: some View {
        List {
            Section {
                HStack {
                    Circle()
                        .fill(server.isRunning ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    Text(server.isRunning ? "服务运行中" : "服务未启动")
                        .font(.headline)
                }
            }

            Section("访问地址") {
                if server.isRunning {
                    ForEach(server.accessURLs, id: \.self) { url in
                        Text(url)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                } else {
                    Text("启动后显示地址")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("· 127.0.0.1 是手机本机回环地址，只能本机自测\n· 电脑访问请用局域网 IP（192.168.x.x 等），需与手机在同一 Wi-Fi")
            }

            Section("说明") {
                Text("服务指向本应用“我的图片”文件夹。电脑浏览器打开地址可浏览、下载文件；用 curl 或支持 WebDAV 的文件管理器可上传文件（PUT）。文件保存在 App 内，仅局域网传输。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("局域网映射")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(server.isRunning ? "停止" : "启动") {
                    server.isRunning ? server.stop() : server.start()
                }
            }
        }
        .onDisappear {
            server.stop()
        }
    }
}
