import Foundation

struct Connection: Codable, Equatable {
    enum Authentication: String, Codable { case apiKey, deviceToken }
    var address: String
    var key: String
    var authentication: Authentication = .apiKey
    var deviceID: Int?

    init(address: String, key: String, authentication: Authentication = .apiKey, deviceID: Int? = nil) {
        self.address = address; self.key = key; self.authentication = authentication; self.deviceID = deviceID
    }

    private enum CodingKeys: String, CodingKey { case address, key, authentication, deviceID }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        address = try values.decode(String.self, forKey: .address)
        key = try values.decode(String.self, forKey: .key)
        authentication = try values.decodeIfPresent(Authentication.self, forKey: .authentication) ?? .apiKey
        deviceID = try values.decodeIfPresent(Int.self, forKey: .deviceID)
    }

    var url: URL { URL(string: address)! }

    static func validated(address: String, key: String, authentication: Authentication = .apiKey, deviceID: Int? = nil) throws -> Connection {
        guard var parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else {
            throw PanelError.message("请输入完整的 HTTPS 面板地址，例如 https://panel.example.com")
        }
        let secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else { throw PanelError.message("请输入面板访问密钥") }
        parts.path = ""
        return Connection(address: parts.string!, key: secret, authentication: authentication, deviceID: deviceID)
    }
}

struct OVHAccount: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let endpoint: String
    let zone: String
    let isDefault: Bool
    var region: String { endpoint.hasSuffix("-us") ? "US" : endpoint.hasSuffix("-ca") ? "CA" : "EU" }
    var regionName: String { region == "US" ? "美国" : region == "CA" ? "加拿大" : "欧洲" }
    var currency: String { NativeCatalog.shared.subsidiaries.first { $0.code == zone }?.currency ?? "—" }
}
struct AccountsResponse: Decodable { let accounts: [OVHAccount] }

struct DashboardStats: Decodable {
    let activeQueues: Int
    let totalServers: Int
    let availableServers: Int
    let purchaseSuccess: Int
    let purchaseFailed: Int
    let queueProcessorRunning: Bool?
    let monitorRunning: Bool?
}

/// Resources of the panel host, shared with the web dashboard's /system/metrics.
struct SystemMetrics: Decodable {
    struct CPU: Decodable {
        let percent: Double
        let cores: Int
        var usage: Double? { cores > 0 ? SystemMetrics.validPercent(percent) : nil }
    }
    struct Memory: Decodable {
        let totalBytes: Double
        let usedBytes: Double
        let percent: Double
        var usage: Double? { SystemMetrics.validCapacity(total: totalBytes, used: usedBytes) ? SystemMetrics.validPercent(percent) : nil }
    }
    struct Disk: Decodable {
        let totalBytes: Double
        let usedBytes: Double
        let percent: Double
        let path: String
        var usage: Double? { SystemMetrics.validCapacity(total: totalBytes, used: usedBytes) ? SystemMetrics.validPercent(percent) : nil }
    }
    let cpu: CPU
    let memory: Memory
    let disk: Disk

    static func validPercent(_ value: Double) -> Double? {
        value.isFinite && (0...100).contains(value) ? value : nil
    }
    private static func validCapacity(total: Double, used: Double) -> Bool {
        total.isFinite && used.isFinite && total > 0 && used >= 0 && used <= total
    }
    static func bytes(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "—" }
        if value < 1024 { return String(format: "%.0f B", locale: Locale(identifier: "en_US_POSIX"), value) }
        let units = ["KB", "MB", "GB", "TB", "PB"]
        var amount = value / 1024, index = 0
        while amount >= 1024 && index < units.count - 1 { amount /= 1024; index += 1 }
        return String(format: "%.1f %@", locale: Locale(identifier: "en_US_POSIX"), amount, units[index])
    }
}

enum ResourceTone {
    case normal, warning, critical
    init(percent: Double) { self = percent >= 85 ? .critical : percent >= 60 ? .warning : .normal }
}

struct QueueItem: Decodable, Identifiable {
    let id: String
    let accountId: String
    let planCode: String
    let datacenter: String
    let status: String
    var statusLabel: String {
        ["pending": "等待库存", "running": "运行中", "paused": "已暂停", "completed": "已完成", "failed": "失败"][status] ?? status
    }
}

enum AssetKind: String, CaseIterable { case dedicated, vps
    var title: String { self == .dedicated ? "独立服务器" : "VPS" }
    var symbol: String { self == .dedicated ? "server.rack" : "square.stack.3d.up.fill" }
    var apiPath: String { self == .dedicated ? "/server-control" : "/vps-control" }
    var consolePath: String { self == .dedicated ? "/server-control" : "/vps-control" }
}
struct DedicatedServer: Decodable {
    let serviceName: String
    let name: String?
    let commercialRange: String?
    let datacenter: String?
    let state: String?
    let ip: String?
    let os: String?
    let renewalType: Bool?
    let error: String?
    let svcInfoError: String?
}
struct DedicatedResponse: Decodable { let servers: [DedicatedServer] }
struct VPS: Decodable {
    let serviceName: String
    let displayName: String?
    let state: String?
    let zone: String?
    let vcore: Int?
    let memoryMB: Int?
    let diskGB: Int?
    let renewalType: Bool?
    let model: String?
    let error: String?
}
struct VPSResponse: Decodable { let vps: [VPS] }

struct Asset: Identifiable, Hashable {
    let serviceName: String
    let name: String
    let kind: AssetKind
    let state: String
    let location: String
    let specification: String
    let ip: String?
    let os: String?
    let renewal: Bool?
    let issue: String?
    var id: String { kind.rawValue + ":" + serviceName }
    var healthy: Bool { ["ok", "active", "running"].contains(state.lowercased()) && issue == nil }
    var stateLabel: String {
        ["ok": "正常", "active": "正常", "running": "运行中", "stopped": "已关机", "suspended": "已暂停", "installing": "安装中", "migrating": "迁移中", "unknown": "状态未知"][state] ?? state
    }
    init(_ server: DedicatedServer) {
        serviceName = server.serviceName; name = server.name ?? server.serviceName; kind = .dedicated
        state = server.state ?? "unknown"; location = (server.datacenter ?? "未知机房").uppercased()
        specification = server.commercialRange ?? "配置未获取"; ip = server.ip; os = server.os
        renewal = server.renewalType; issue = server.error ?? server.svcInfoError
    }
    init(_ vps: VPS) {
        serviceName = vps.serviceName; name = vps.displayName ?? vps.serviceName; kind = .vps
        state = vps.state ?? "unknown"; location = vps.zone?.contains("west-or") == true ? "俄勒冈 · 美国" : (vps.zone ?? "未知机房")
        specification = "\(vps.vcore ?? 0) vCPU · \((vps.memoryMB ?? 0) / 1024) GB · \(vps.diskGB ?? 0) GB"
        ip = nil; os = nil; renewal = vps.renewalType; issue = vps.error
    }
}

struct AssetRoute: Hashable {
    let asset: Asset
    let accountID: String
    let accountName: String
}

enum JSONValue: Codable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    subscript(key: String) -> JSONValue { if case .object(let v) = self { return v[key] ?? .null }; return .null }
    var text: String? {
        switch self { case .string(let v): return v; case .number(let v): return v.formatted(); case .bool(let v): return v ? "是" : "否"; default: return nil }
    }
    var array: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    var object: [String: JSONValue] { if case .object(let v) = self { return v }; return [:] }
    var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    var number: Double? { if case .number(let v) = self { return v }; return nil }
    var rawText: String { switch self { case .string(let v): return v; case .number(let v): return v == v.rounded() ? String(format: "%.0f", v) : String(v); case .bool(let v): return String(v); default: return "" } }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .null: try c.encodeNil(); case .string(let v): try c.encode(v); case .number(let v): try c.encode(v); case .bool(let v): try c.encode(v); case .object(let v): try c.encode(v); case .array(let v): try c.encode(v) }
    }
}

enum PanelError: LocalizedError {
    case unauthorized, message(String)
    var errorDescription: String? {
        switch self { case .unauthorized: return "面板访问密钥已失效，请重新连接"; case .message(let value): return value }
    }
}

struct ConsoleDestination: Identifiable, Hashable {
    let path: String
    let title: String
    var id: String { path }
    static let all = [
        ConsoleDestination(path: "/servers", title: "服务器列表"),
        ConsoleDestination(path: "/queue", title: "抢购队列"),
        ConsoleDestination(path: "/monitor", title: "服务器监控"),
        ConsoleDestination(path: "/vps-monitor", title: "VPS 补货"),
        ConsoleDestination(path: "/server-control", title: "服务器控制"),
        ConsoleDestination(path: "/vps-control", title: "VPS 控制"),
        ConsoleDestination(path: "/history", title: "抢购历史"),
        ConsoleDestination(path: "/account", title: "账户管理"),
        ConsoleDestination(path: "/logs", title: "详细日志"),
        ConsoleDestination(path: "/settings", title: "API 设置")
    ]
}
