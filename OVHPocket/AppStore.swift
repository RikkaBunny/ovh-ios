import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var connection: Connection?
    @Published private(set) var accounts: [OVHAccount] = []
    @Published private(set) var assets: [Asset] = []
    @Published private(set) var stats: DashboardStats?
    @Published private(set) var systemMetrics: SystemMetrics?
    @Published private(set) var metricsLoading = false
    @Published private(set) var metricsError: String?
    @Published private(set) var queue: [QueueItem] = []
    @Published var selectedAccountID = ""
    @Published var loading = false
    @Published var connecting = false
    @Published var error: String?
    @Published var refreshedAt: Date?
    @Published var consoleDestination: ConsoleDestination?
    @Published var selectedTab = 0
    @Published var navigationPaths = (0..<5).map { _ in NavigationPath() }
    @Published var nativeRevision = 0
    @Published var sessionID = UUID()
    @Published var showPairing = false
    private var revision = 0
    private var metricsRevision = 0
    private var refreshTask: Task<Void, Never>?
    private var refreshScope = ""
    private var refreshIncludesAccounts = false
    typealias Fetch = (Connection, String, String?) async throws -> JSONValue
    private let fetch: Fetch

    var activeAccount: OVHAccount? { accounts.first { $0.id == selectedAccountID } }
    var accountQueue: [QueueItem] { queue.filter { $0.accountId == selectedAccountID } }
    var serverCount: Int { assets.filter { $0.kind == .dedicated }.count }
    var vpsCount: Int { assets.filter { $0.kind == .vps }.count }

    init(fetch: @escaping Fetch = { connection, path, account in
        try await APIClient(connection: connection).value(path, account: account).value
    }) {
        self.fetch = fetch
        connection = CredentialStore.load(); selectedAccountID = UserDefaults.standard.string(forKey: "selectedAccountID") ?? ""
    }

    private func read<T: Decodable>(_ path: String, connection: Connection, account: String? = nil) async throws -> T {
        let value = try await fetch(connection, path, account)
        try Task.checkCancellation()
        return try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    func start() async {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["OVH_NATIVE_QA"] == "1", ProcessInfo.processInfo.environment["OVH_BOOTSTRAP_ADDRESS"] == "https://localhost:16443" { disconnect() }
        if connection == nil, let key = ProcessInfo.processInfo.environment["OVH_BOOTSTRAP_KEY"] {
            await connect(address: ProcessInfo.processInfo.environment["OVH_BOOTSTRAP_ADDRESS"] ?? "https://ovh.hejingcheng.com", key: key)
            return
        }
        #endif
        if connection != nil { await reconnect() }
    }

    func connect(address: String, key: String) async {
        connecting = true; error = nil
        defer { connecting = false }
        do {
            let candidate = try Connection.validated(address: address, key: key)
            try await establish(candidate)
        } catch { self.error = error.localizedDescription; if case PanelError.unauthorized = error { disconnect() } }
    }

    func reconnect() async {
        guard let connection, !connecting else { return }
        connecting = true; error = nil
        defer { connecting = false }
        do { try await establish(connection) }
        catch { self.error = error.localizedDescription; if case PanelError.unauthorized = error { invalidate(connection) } }
    }

    private func establish(_ candidate: Connection) async throws {
        let result: AccountsResponse = try await read("/accounts", connection: candidate)
        try CredentialStore.save(candidate)
        cancelRefresh(); sessionID = UUID(); resetSystemMetrics(); connection = candidate; accounts = result.accounts
        chooseAvailableAccount()
        await refresh(includeAccounts: false)
    }

    @discardableResult
    func pair(address: String, code: String, deviceName: String) async -> Bool {
        guard !connecting else { return false }
        connecting = true; error = nil
        defer { connecting = false }
        do {
            let candidate = try await APIClient.pair(address: address, code: code, deviceName: deviceName)
            // Persist the one-time response before loading assets: a temporary
            // network failure must not lose a consumed code's device token.
            try CredentialStore.save(candidate)
            cancelRefresh(); sessionID = UUID(); resetSystemMetrics(); connection = candidate
            accounts = []; assets = []; queue = []; stats = nil; refreshedAt = nil
            showPairing = false
            do { try await establish(candidate) }
            catch { self.error = error.localizedDescription; if case PanelError.unauthorized = error { invalidate(candidate); return false } }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    private func chooseAvailableAccount() {
        if !accounts.contains(where: { $0.id == selectedAccountID }) {
            selectedAccountID = accounts.first(where: \.isDefault)?.id ?? accounts.first?.id ?? ""
        }
        UserDefaults.standard.set(selectedAccountID, forKey: "selectedAccountID")
    }

    func invalidate(_ failedConnection: Connection) {
        guard connection == failedConnection else { return }
        disconnect()
        error = failedConnection.authentication == .deviceToken ? "此设备的授权已失效或被撤销，请在网页重新生成配对码" : PanelError.unauthorized.localizedDescription
    }

    func selectAccount(_ id: String) {
        guard id != selectedAccountID, accounts.contains(where: { $0.id == id }) else { return }
        cancelRefresh(); selectedAccountID = id; assets = []; refreshedAt = nil; error = nil
        UserDefaults.standard.set(id, forKey: "selectedAccountID")
        Task { await refresh(includeAccounts: false) }
    }

    func refresh(includeAccounts: Bool = true) async {
        guard let connection else { return }
        let scope = sessionID.uuidString + "|" + selectedAccountID
        if let refreshTask, refreshScope == scope, !includeAccounts || refreshIncludesAccounts {
            await refreshTask.value; return
        }
        cancelRefresh()
        let current = revision
        refreshScope = scope; refreshIncludesAccounts = includeAccounts
        let session = sessionID
        let request = Task { await self.loadOverview(connection: connection, session: session, current: current, includeAccounts: includeAccounts) }
        refreshTask = request
        await request.value
        if revision == current { refreshTask = nil }
    }

    private func cancelRefresh() {
        revision += 1; refreshTask?.cancel(); refreshTask = nil; loading = false
    }

    private func loadOverview(connection: Connection, session: UUID, current: Int, includeAccounts: Bool) async {
        guard !Task.isCancelled, revision == current, sessionID == session, self.connection == connection else { return }
        loading = true; error = nil
        defer { if revision == current { loading = false } }
        var issues: [String] = []
        if includeAccounts {
            do {
                let result: AccountsResponse = try await read("/accounts", connection: connection)
                guard !Task.isCancelled, current == revision, sessionID == session, self.connection == connection else { return }
                let previousAccount = selectedAccountID
                accounts = result.accounts; chooseAvailableAccount()
                if previousAccount != selectedAccountID { assets = []; refreshedAt = nil }
                refreshScope = session.uuidString + "|" + selectedAccountID
            } catch {
                guard !Task.isCancelled, !APIClient.isCancellation(error), current == revision, sessionID == session, self.connection == connection else { return }
                if case PanelError.unauthorized = error { invalidate(connection); return }
                issues.append("账户：" + error.localizedDescription)
            }
        }
        let account = selectedAccountID
        async let statResult: Result<DashboardStats, Error> = capture { try await self.read("/stats", connection: connection) }
        async let queueResult: Result<[QueueItem], Error> = capture { try await self.read("/queue", connection: connection) }
        async let serverResult: Result<DedicatedResponse, Error> = capture { try await self.read("/server-control/list", connection: connection, account: account) }
        async let vpsResult: Result<VPSResponse, Error> = capture { try await self.read("/vps-control/list", connection: connection, account: account) }
        let results = await (statResult, queueResult, serverResult, vpsResult)
        guard !Task.isCancelled, revision == current, sessionID == session, self.connection == connection, selectedAccountID == account else { return }
        let failures = [results.0.failure, results.1.failure, results.2.failure, results.3.failure].compactMap { $0 }
        if failures.contains(where: { if case PanelError.unauthorized = $0 { return true }; return false }) { invalidate(connection); return }
        func failure(_ value: Error, section: String) {
            guard !APIClient.isCancellation(value) else { return }
            issues.append(section + "：" + value.localizedDescription)
        }
        switch results.0 { case .success(let value): stats = value; case .failure(let e): failure(e, section: "概览") }
        switch results.1 { case .success(let value): queue = value; case .failure(let e): failure(e, section: "队列") }
        var loaded: [Asset] = []
        switch results.2 { case .success(let value): loaded += value.servers.map(Asset.init); case .failure(let e): loaded += assets.filter { $0.kind == .dedicated }; failure(e, section: "独服") }
        switch results.3 { case .success(let value): loaded += value.vps.map(Asset.init); case .failure(let e): loaded += assets.filter { $0.kind == .vps }; failure(e, section: "VPS") }
        assets = loaded
        if failures.isEmpty && issues.isEmpty { refreshedAt = Date() }
        error = issues.isEmpty ? nil : issues.joined(separator: "\n")
    }

    func openConsole(_ destination: ConsoleDestination) { navigationPaths[selectedTab].append(destination) }

    func refreshSystemMetrics() async {
        guard let connection, !metricsLoading, !Task.isCancelled else { return }
        metricsRevision += 1
        let current = metricsRevision, session = sessionID
        metricsLoading = true
        defer { if current == metricsRevision { metricsLoading = false } }
        do {
            let metrics: SystemMetrics = try await APIClient(connection: connection).request("/system/metrics")
            guard !Task.isCancelled, current == metricsRevision, session == sessionID, self.connection == connection else { return }
            systemMetrics = metrics; metricsError = nil
        } catch {
            guard !Task.isCancelled, current == metricsRevision, session == sessionID, self.connection == connection else { return }
            if case PanelError.unauthorized = error { invalidate(connection); return }
            guard !APIClient.isCancellation(error) else { return }
            systemMetrics = nil; metricsError = error.localizedDescription
        }
    }

    private func resetSystemMetrics() {
        metricsRevision += 1; systemMetrics = nil; metricsError = nil; metricsLoading = false
    }

    func disconnect() {
        cancelRefresh(); CredentialStore.remove(); connection = nil; accounts = []; assets = []; queue = []; stats = nil
        resetSystemMetrics()
        selectedAccountID = ""; loading = false; refreshedAt = nil; consoleDestination = nil; sessionID = UUID(); showPairing = false
        navigationPaths = (0..<5).map { _ in NavigationPath() }
        UserDefaults.standard.removeObject(forKey: "selectedAccountID")
    }
}

func capture<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
    do { return .success(try await operation()) } catch { return .failure(error) }
}

private extension Result where Failure == Error {
    var failure: Error? { if case .failure(let error) = self { return error }; return nil }
}

@MainActor
final class AssetDetailStore: ObservableObject {
    @Published var rows: [(String, String)] = []
    @Published var ips: [String] = []
    @Published var loading = false
    @Published var error: String?
    @Published var actionMessage: String?
    @Published var submitting = false
    private var revision = 0
    private var resource = ""
    private var resourceConnection: Connection?

    func load(asset: Asset, connection: Connection, account: String) async {
        guard !Task.isCancelled else { return }
        let identity = account + "|" + asset.kind.rawValue + "|" + asset.serviceName
        if resource != identity || resourceConnection != connection {
            rows = []; ips = []; resource = identity; resourceConnection = connection
        }
        revision += 1
        let ticket = revision
        loading = true; error = nil
        defer { if revision == ticket { loading = false } }
        let client = APIClient(connection: connection), root = asset.kind.apiPath + "/" + APIClient.component(asset.serviceName)
        async let service: Result<JSONValue, Error> = capture { try await client.request(root + "/serviceinfo", account: account) }
        async let information: Result<JSONValue, Error> = capture { try await client.request(root + (asset.kind == .vps ? "/current-os" : "/hardware"), account: account) }
        async let addresses: Result<JSONValue, Error> = capture { try await client.request(root + "/ips", account: account) }
        let result = await (service, information, addresses)
        guard !Task.isCancelled, revision == ticket else { return }
        var errors: [String] = [], loaded: [(String, String)] = []
        var loadedIPs: [String] = ips
        func failure(_ error: Error, section: String) {
            if !APIClient.isCancellation(error) { errors.append(section + error.localizedDescription) }
        }
        if let os = asset.os { loaded.append(("操作系统", os)) }
        switch result.0 {
        case .success(let response):
            let info = response["serviceInfo"]
            if let expiration = info["expiration"].text { loaded.append(("到期时间", String(expiration.prefix(10)))) }
            if let automatic = info["renewalType"].text { loaded.append(("自动续费", automatic)) }
            if let period = info["renewalPeriod"].text { loaded.append(("续费周期", period + " 个月")) }
        case .failure(let e): failure(e, section: "续费信息：")
        }
        switch result.1 {
        case .success(let response):
            if asset.kind == .vps {
                if let name = response["currentOS"]["name"].text { loaded.append(("操作系统", name)) }
            } else {
                let hw = response["hardware"]
                if let cpu = hw["processorName"].text { loaded.append(("处理器", cpu)) }
                if let memory = hw["memorySize"]["value"].text { loaded.append(("内存", memory + " " + (hw["memorySize"]["unit"].text ?? "MB"))) }
            }
        case .failure(let e): failure(e, section: "配置信息：")
        }
        switch result.2 {
        case .success(let response):
            loadedIPs = response["ips"].array.compactMap { $0["ipAddress"].text ?? $0["ip"].text ?? $0.text }
        case .failure(let e): failure(e, section: "IP 地址：")
        }
        if result.0.failure == nil, result.1.failure == nil, result.2.failure == nil { rows = loaded; ips = loadedIPs }
        error = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    func perform(_ action: String, asset: Asset, connection: Connection, account: String) async {
        submitting = true; error = nil
        defer { submitting = false }
        do {
            let result: JSONValue = try await APIClient(connection: connection).request(asset.kind.apiPath + "/" + asset.serviceName + "/" + action,
                account: account, method: "POST", body: Data("{}".utf8))
            if result["success"].text == "否" { throw PanelError.message(result["error"].text ?? "操作未成功") }
            actionMessage = "请求已提交，等待 OVH 执行。请稍后刷新状态。"
        } catch { self.error = error.localizedDescription }
    }
}
