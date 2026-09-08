//
//  RemoteMountScanner.swift
//  PhotoViewer
//
//  IP 映射挂载：通过局域网地址扫描远端目录（不拷贝文件，在线直读）。
//  支持三种来源：
//   1. WebDAV（PROPFIND，支持 NAS / Nginx dav / Apache mod_dav）
//   2. 普通 HTTP 目录列表（Python http.server / Nginx autoindex / Apache）
//   3. 单个媒体文件 URL（直接挂载该文件）
//  返回 items：url 为远端 http(s) 直链，网页通过 <img>/<video> 在线加载。
//

import Foundation

struct RemoteMediaItem {
    var name: String
    var url: String
    var type: String   // "image" | "video"
    var size: Int
    var relPath: String
}

class RemoteMountScanner {

    private static let maxDepth = 3
    private static let mediaExts = ["jpg","jpeg","png","gif","webp","bmp","svg","heic","heif","mp4","mov","avi","mkv","webm","flv","wmv","m4v","3gp"]
    private static let videoExts = ["mp4","mov","avi","mkv","webm","flv","wmv","m4v","3gp"]

    static func isMediaFile(_ name: String) -> Bool {
        mediaExts.contains((name as NSString).pathExtension.lowercased())
    }

    static func isVideoFile(_ name: String) -> Bool {
        videoExts.contains((name as NSString).pathExtension.lowercased())
    }

    /// 扫描入口：baseURL 可以是目录或单个媒体文件
    static func scan(baseURL: URL, completion: @escaping ([RemoteMediaItem]?) -> Void) {
        // 1) 直接是媒体文件？
        if isMediaFile(baseURL.lastPathComponent) {
            let item = RemoteMediaItem(name: baseURL.lastPathComponent,
                                       url: baseURL.absoluteString,
                                       type: isVideoFile(baseURL.lastPathComponent) ? "video" : "image",
                                       size: 0,
                                       relPath: baseURL.lastPathComponent)
            completion([item])
            return
        }

        // 2) 扫描目录
        scanDirectory(url: baseURL, depth: 0) { result in
            if let result = result {
                completion(result)
            } else {
                completion(nil)  // 目录访问失败
            }
        }
    }

    // MARK: - 目录扫描（先尝试 WebDAV，失败后回退 HTML 列表）

    private static func scanDirectory(url: URL, depth: Int, done: @escaping ([RemoteMediaItem]?) -> Void) {
        if depth >= maxDepth {
            done([])
            return
        }

        webdavList(url: url) { davResult in
            if let davItems = davResult {
                // WebDAV 成功
                collect(davItems, depth: depth, done: done)
            } else {
                // 回退 HTML 目录列表
                htmlList(url: url) { htmlItems in
                    if let htmlItems = htmlItems {
                        collect(htmlItems, depth: depth, done: done)
                    } else {
                        done(nil)
                    }
                }
            }
        }
    }

    private static func collect(_ found: [(name: String, url: URL, size: Int, isDir: Bool)], depth: Int, done: @escaping ([RemoteMediaItem]?) -> Void) {
        // 先收集本层媒体文件
        var items: [RemoteMediaItem] = []
        for f in found where !f.isDir && isMediaFile(f.name) {
            items.append(RemoteMediaItem(name: f.name,
                                         url: f.url.absoluteString,
                                         type: isVideoFile(f.name) ? "video" : "image",
                                         size: f.size,
                                         relPath: f.name))
        }
        // 递归子目录（子目录失败只跳过，不致命）
        let dirs = found.filter { $0.isDir }
        if dirs.isEmpty {
            done(items)
            return
        }
        let group = DispatchGroup()
        var collectedSub: [RemoteMediaItem] = []
        let lock = NSLock()
        for d in dirs {
            group.enter()
            scanDirectory(url: d.url, depth: depth + 1) { sub in
                lock.lock()
                if let sub = sub {
                    collectedSub.append(contentsOf: sub)
                }
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) {
            lock.lock()
            items.append(contentsOf: collectedSub)
            lock.unlock()
            done(items)
        }
    }

    // MARK: - WebDAV PROPFIND

    private static func webdavList(url: URL, completion: @escaping ([(name: String, url: URL, size: Int, isDir: Bool)]?) -> Void) {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:"><d:prop>
        <d:displayname/><d:getcontentlength/><d:resourcetype/><d:getcontenttype/>
        </d:prop></d:propfind>
        """
        request.httpBody = Data(body.utf8)

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil, let data = data,
                  let http = response as? HTTPURLResponse,
                  (http.statusCode == 207 || http.statusCode == 200),
                  let xml = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let parsed = parseWebDAV(xml, baseURL: url)
            DispatchQueue.main.async { completion(parsed) }
        }.resume()
    }

    private static func parseWebDAV(_ xml: String, baseURL: URL) -> [(name: String, url: URL, size: Int, isDir: Bool)]? {
        // 提取每个 <response> 块
        let responsePattern = "<(?<t>[a-zA-Z0-9]+):response>(.*?)</\\k<t>:response>"
        let blocks = regexMatches(responsePattern, in: xml)
        guard !blocks.isEmpty else { return nil }

        var result: [(name: String, url: URL, size: Int, isDir: Bool)] = []
        let basePath = baseURL.path

        for block in blocks {
            guard let href = firstMatch("<([a-zA-Z0-9]+):href>(.*?)</\\1:href>", in: block) else { continue }
            let hrefValue = decodeXML(href).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hrefValue.isEmpty else { continue }

            // 解析为 URL（统一转为绝对 URL，避免相对路径比较出错）
            guard let resolved = absoluteURL(hrefValue, relativeTo: baseURL) else { continue }

            // 父目录自身（== base）跳过
            if resolved.path == basePath || resolved.path == basePath + "/" { continue }

            let isDir = block.contains("collection")
            let sizeStr = firstMatch("<([a-zA-Z0-9]+):getcontentlength>(.*?)</\\1:getcontentlength>", in: block) ?? ""
            let size = Int(sizeStr) ?? 0
            let name = resolved.lastPathComponent.isEmpty ? "未命名" : resolved.lastPathComponent

            if isDir {
                result.append((name, resolved, 0, true))
            } else {
                result.append((name, resolved, size, false))
            }
        }
        return result
    }

    // MARK: - HTML 目录列表

    private static func htmlList(url: URL, completion: @escaping ([(name: String, url: URL, size: Int, isDir: Bool)]?) -> Void) {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil, let data = data,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let contentType = http.allHeaderFields["Content-Type"] as? String ?? ""
            if contentType.contains("text/html") || contentType.isEmpty {
                guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                let parsed = parseHTMLList(html, baseURL: url)
                DispatchQueue.main.async { completion(parsed) }
            } else {
                DispatchQueue.main.async { completion([]) }
            }
        }.resume()
    }

    private static func parseHTMLList(_ html: String, baseURL: URL) -> [(name: String, url: URL, size: Int, isDir: Bool)]? {
        let linkPattern = "<a[^>]+href=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>"
        let matches = regexMatchesPairs(linkPattern, in: html)
        guard !matches.isEmpty else { return nil }

        var result: [(name: String, url: URL, size: Int, isDir: Bool)] = []
        for m in matches {
            let href = m.0
            guard !href.isEmpty, !href.hasPrefix("?") else { continue }
            let display = stripHTML(m.1).trimmingCharacters(in: .whitespacesAndNewlines)

            // 父目录链接跳过
            if href.hasSuffix("/../") || href == "../" || href == ".." || display.contains("Parent Directory") {
                continue
            }
            let isDir = href.hasSuffix("/")
            guard let resolved = absoluteURL(href, relativeTo: baseURL) else { continue }

            let name = display.isEmpty ? resolved.lastPathComponent : display
            result.append((name, resolved, 0, isDir))
        }
        return result
    }

    // MARK: - 工具

    /// 将 href（可能相对）解析为绝对 URL
    private static func absoluteURL(_ href: String, relativeTo base: URL) -> URL? {
        if href.hasPrefix("http") {
            return URL(string: href)
        }
        guard let absStr = URL(string: href, relativeTo: base)?.absoluteString else { return nil }
        return URL(string: absStr)
    }

    private static func regexMatches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { m in
            guard m.numberOfRanges > 0, let r = Range(m.range(at: m.numberOfRanges - 1), in: text) else { return nil }
            return String(text[r])
        }
    }

    private static func regexMatchesPairs(_ pattern: String, in text: String) -> [(String, String)] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { m in
            guard let r1 = Range(m.range(at: 1), in: text), let r2 = Range(m.range(at: 2), in: text) else { return nil }
            return (String(text[r1]), String(text[r2]))
        }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, options: [], range: range),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: m.numberOfRanges - 1), in: text) else { return nil }
        // 取最后一个捕获组（内容），如 <d:href>CONTENT</d:href> 中的 CONTENT
        return String(text[r])
    }

    private static func decodeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
         .replacingOccurrences(of: "&lt;", with: "<")
         .replacingOccurrences(of: "&gt;", with: ">")
         .replacingOccurrences(of: "&quot;", with: "\"")
         .replacingOccurrences(of: "&#39;", with: "'")
    }

    private static func stripHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
