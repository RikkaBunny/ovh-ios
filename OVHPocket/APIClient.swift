import Foundation

final class SameOriginRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let origin: URL
    init(origin: URL) { self.origin = origin }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == origin.scheme, url.host == origin.host, url.port == origin.port else {
            completionHandler(nil); return
        }
        completionHandler(request)
    }
}

struct APIClient {
    let connection: Connection
    // URLSession uses URLError.cancelled, while structured tasks can throw CancellationError.
    // Never classify an actual server error by matching its human-readable message.
    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
    static func cacheWarning(_ warning: String) -> String {
        guard warning.hasPrefix("Using expired cache") else { return warning }
        let minutes = warning.split(whereSeparator: { !$0.isNumber }).first.map(String.init)
        return "当前展示旧目录缓存" + (minutes.map { "（\($0) 分钟前）" } ?? "") + "，请刷新目录或进入机型详情查询实时库存。"
    }
    static func component(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? ""
    }
    func makeRequest(_ path: String, account: String? = nil, method: String = "GET", body: Data? = nil, query: [String: String] = [:]) -> URLRequest {
        var parts = URLComponents(url: connection.url, resolvingAgainstBaseURL: false)!
        let relative = URLComponents(string: path)!
        parts.percentEncodedPath = "/api" + relative.percentEncodedPath
        var items = relative.queryItems ?? []
        items.removeAll { $0.name == "account" || query[$0.name] != nil }
        items += query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        if let account, !account.isEmpty { items.append(URLQueryItem(name: "account", value: account)) }
        parts.queryItems = items.isEmpty ? nil : items
        var request = URLRequest(url: parts.url!)
        request.timeoutInterval = 60
        request.httpMethod = method
        request.httpBody = body
        if connection.authentication == .deviceToken {
            request.setValue("Bearer " + connection.key, forHTTPHeaderField: "Authorization")
        } else {
            request.setValue(connection.key, forHTTPHeaderField: "X-API-Key")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 OVHPocket/1.0", forHTTPHeaderField: "User-Agent")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    func request<T: Decodable>(_ path: String, account: String? = nil, method: String = "GET", body: Data? = nil, query: [String: String] = [:]) async throws -> T {
        try await Self.send(makeRequest(path, account: account, method: method, body: body, query: query), origin: connection.url)
    }
    func value(_ path: String, account: String? = nil, method: String = "GET", body: JSONValue? = nil, query: [String: String] = [:]) async throws -> APIResponse<JSONValue> {
        let data = try body.map { try JSONEncoder().encode($0) }
        let result: APIResponse<JSONValue> = try await Self.response(makeRequest(path, account: account, method: method, body: data, query: query), origin: connection.url)
        if result.value["success"].bool == false || result.value["status"].text == "error" {
            throw PanelError.message(result.value["error"].text ?? result.value["message"].text ?? "操作未成功")
        }
        return result
    }

    static func send<T: Decodable>(_ request: URLRequest, origin: URL, pairing: Bool = false) async throws -> T {
        let result: APIResponse<T> = try await response(request, origin: origin, pairing: pairing)
        return result.value
    }
    static func response<T: Decodable>(_ request: URLRequest, origin: URL, pairing: Bool = false) async throws -> APIResponse<T> {
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config, delegate: SameOriginRedirect(origin: origin), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw PanelError.message("面板返回了无法识别的响应") }
        if http.statusCode == 401 { throw PanelError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(JSONValue.self, from: data)
            if pairing && http.statusCode == 404 { throw PanelError.message("此面板尚未提供 App 配对，请更新后端或使用访问密钥连接") }
            throw PanelError.message(error?["message"].text ?? error?["error"].text ?? "面板请求失败（HTTP \(http.statusCode)）")
        }
        var notices: [String] = []
        if let n = http.value(forHTTPHeaderField: "X-Partial-Failures"), n != "0" { notices.append("部分明细未能获取（\(n) 项），请重试") }
        if let warning = http.value(forHTTPHeaderField: "X-Cache-Warning"), !warning.isEmpty { notices.append(cacheWarning(warning)) }
        if http.value(forHTTPHeaderField: "X-Subsidiary-Mismatch") == "1" { notices.append("账户所属站点与当前区域不一致，请检查账户设置") }
        do { return APIResponse(value: try JSONDecoder().decode(T.self, from: data.isEmpty ? Data("null".utf8) : data), notices: notices) }
        catch { throw PanelError.message("面板数据格式无法识别，请检查地址或面板版本") }
    }
}

struct APIResponse<T> {
    let value: T
    let notices: [String]
}
