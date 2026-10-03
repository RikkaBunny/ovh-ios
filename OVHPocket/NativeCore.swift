import SwiftUI
import CoreImage.CIFilterBuiltins

struct NativeField: Decodable, Identifiable {
    let key: String
    let label: String
    let kind: String
    let location: String
    let required: Bool
    var choices: [String]?
    var children: [NativeField]?
    var id: String { location + ":" + key }
    var numeric: Bool { kind == "number" }
}

struct NativeOperation: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let group: String
    let scope: String
    let method: String
    let path: String
    let fields: [NativeField]
    let danger: Bool
    let source: String
    let handler: String
    static func ==(lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    var isRead: Bool { method == "GET" }
    var globalTarget: String? {
        ["/queue/clear":"所有账户的抢购队列","/purchase-history":"所有账户的抢购历史","/monitor/subscriptions/clear":"全部服务器监控订阅","/vps-monitor/subscriptions/clear":"全部 VPS 监控订阅","/logs":"整个面板的日志" ][path]
    }
    func resolve(values: [String: JSONValue], context: NativeContext) throws -> (String, [String: String], JSONValue?) {
        var route = path
        if let service = context.service { route = route.replacingOccurrences(of: ":service_name", with: APIClient.component(service)) }
        var query: [String: String] = [:], body: [String: JSONValue] = [:]
        for field in fields {
            let value = context.bindings[field.key] ?? values[field.key]
            let empty = value == nil || value == .null || value == .string("")
            if field.required && empty { throw PanelError.message("请填写" + field.label) }
            guard let value, value != .null else { continue }
            if empty && field.location != "body" { continue }
            if field.kind == "number", value.number == nil { throw PanelError.message(field.label + "必须是数字") }
            if ["quantity"].contains(field.key), let n = value.number, !(1...20).contains(n) { throw PanelError.message("每个机房数量必须在 1～20 之间") }
            if ["retryInterval","interval","check_interval","defaultRetryInterval","quickOrderRetryInterval"].contains(field.key), let n = value.number, !(1...86400).contains(n) { throw PanelError.message("间隔必须在 1～86400 秒之间") }
            switch field.location {
            case "path": route = route.replacingOccurrences(of: ":" + field.key, with: APIClient.component(value.rawText)).replacingOccurrences(of: "*" + field.key, with: APIClient.component(value.rawText))
            case "query": query[field.key] = value.rawText
            default: body[field.key] = value
            }
        }
        guard !route.contains(":"), !route.contains("*") else { throw PanelError.message("请选择完整的操作目标") }
        return (route, query, isRead ? nil : .object(body))
    }
}

struct NativeContext: Hashable {
    var account: String
    var accountName: String
    var service: String?
    var bindings: [String: JSONValue] = [:]
    static func ==(lhs: Self, rhs: Self) -> Bool { lhs.account == rhs.account && lhs.service == rhs.service && lhs.bindings == rhs.bindings }
    func hash(into hasher: inout Hasher) { hasher.combine(account); hasher.combine(service) }
}

struct NativeCatalog: Decodable {
    let commit: String
    let operations: [NativeOperation]
    let labels: [String: String]
    let subsidiaries: [NativeSubsidiary]
    static let shared: NativeCatalog = {
        guard let url = Bundle.main.url(forResource: "NativeCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url), let result = try? JSONDecoder().decode(Self.self, from: data) else {
            preconditionFailure("Native feature catalog is missing or invalid")
        }
        return result
    }()
    func operation(_ path: String) -> NativeOperation { operation("GET", path) }
    func operation(_ method: String, _ path: String) -> NativeOperation {
        guard let op = operations.first(where: { $0.method == method && $0.path == path }) else { preconditionFailure("Missing native operation: \(method) \(path)") }
        return op
    }
    static func label(_ key: String) -> String { shared.labels[key] ?? key }
    static func secret(_ key: String) -> Bool { ["appKey","appSecret","consumerKey","tgToken","token","deviceToken","apiKey","password"].contains(key) }
}

struct NativeSubsidiary: Decodable, Identifiable {
    let code: String
    let endpoint: String
    let label: String
    let currency: String
    var id: String { code }
}

/// A pull gesture may cancel its callback before the request finishes. Keep the
/// read alive until it completes, or explicitly cancel it when its page/scope leaves.
@MainActor final class NativeRefreshRequests: ObservableObject {
    private var task: Task<Void, Never>?
    private var scope = ""
    private var revision = 0

    func run(scope: String, operation: @escaping @MainActor () async -> Void) async {
        if let task, self.scope == scope { await task.value; return }
        cancel()
        self.scope = scope
        let ticket = revision
        let request = Task { await operation() }
        task = request
        await request.value
        if revision == ticket { task = nil }
    }

    func cancel() { revision += 1; task?.cancel(); task = nil }
}

private struct NativeRefreshModifier: ViewModifier {
    @EnvironmentObject private var store: AppStore
    @StateObject private var requests = NativeRefreshRequests()
    let scope: String
    let action: @MainActor () async -> Void
    private var identity: String { store.sessionID.uuidString + "|" + store.selectedAccountID + "|" + scope }
    func body(content: Content) -> some View {
        content.refreshable { await requests.run(scope: identity, operation: action) }
            .onChange(of: identity) { _, _ in requests.cancel() }
            .onDisappear { requests.cancel() }
    }
}

extension View {
    func nativeRefreshable(scope: String = "", action: @escaping @MainActor () async -> Void) -> some View {
        modifier(NativeRefreshModifier(scope: scope, action: action))
    }
}

@MainActor final class NativeLoader: ObservableObject {
    @Published var value: JSONValue = .null
    @Published var error: String?
    @Published var notices: [String] = []
    @Published var loading = false
    @Published var updated: Date?
    private var revision = 0
    private var resource = ""
    typealias Fetch = (Connection, String, String?, [String: String]) async throws -> APIResponse<JSONValue>
    private let fetch: Fetch
    init(fetch: @escaping Fetch = { connection, path, account, query in
        try await APIClient(connection: connection).value(path, account: account, query: query)
    }) { self.fetch = fetch }
    func load(_ path: String, store: AppStore, account: String? = nil, query: [String: String] = [:], requireActiveAccount: Bool = false) async {
        guard !Task.isCancelled else { return }
        guard let connection = store.connection else { return }
        // Refresh controls do not describe a different resource. The server's showApiServers
        // flag controls whether to fetch OVH, not a separate list/cache bucket.
        let scopeQuery = query.filter { $0.key != "forceRefresh" && !(path == "/servers" && $0.key == "showApiServers") }
        let identity = APIClient(connection: connection).makeRequest(path, account: account, query: scopeQuery).url!.absoluteString + "|" + store.sessionID.uuidString
        if identity != resource { value = .null; notices = []; updated = nil; resource = identity }
        revision += 1
        let ticket = revision, session = store.sessionID
        loading = true; error = nil
        defer { if revision == ticket { loading = false } }
        do {
            let result = try await fetch(connection, path, account, query)
            guard !Task.isCancelled, revision == ticket, store.sessionID == session, store.connection == connection,
                  !requireActiveAccount || store.selectedAccountID == account else { return }
            value = result.value; notices = result.notices; updated = Date()
        } catch {
            guard !Task.isCancelled, !APIClient.isCancellation(error), revision == ticket,
                  store.sessionID == session, store.connection == connection,
                  !requireActiveAccount || store.selectedAccountID == account else { return }
            self.error = error.localizedDescription
            if case PanelError.unauthorized = error { store.invalidate(connection) }
        }
    }
}

struct NativeOperationLink: View {
    let operation: NativeOperation
    let context: NativeContext
    var seed: [String: JSONValue] = [:]
    var body: some View {
        NavigationLink { NativeOperationView(operation: operation, context: context, seed: seed) } label: {
            HStack(spacing: 12) {
                Image(systemName: operation.isRead ? "doc.text" : operation.danger ? "exclamationmark.circle" : "slider.horizontal.3")
                    .foregroundStyle(operation.danger ? Theme.warning : Theme.muted).frame(width: 22)
                Text(operation.title).font(.system(size: 14))
                Spacer(); Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }.padding(14).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("native." + operation.handler)
    }
}

struct NativeDataView: View {
    let value: JSONValue
    var depth = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch value {
            case .null: Text("暂无数据").font(.system(size: 13)).foregroundStyle(Theme.muted)
            case .array(let values):
                if values.isEmpty { Text("暂无记录").font(.system(size: 13)).foregroundStyle(Theme.muted) }
                ForEach(Array(values.enumerated()), id: \.offset) { item in
                    NativeDataView(value: item.element, depth: depth + 1)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12).panel()
                }
            case .object(let object):
                ForEach(object.keys.sorted().filter { object[$0] != .null && !NativeCatalog.secret($0) }, id: \.self) { key in
                    if let text = object[key]?.text {
                        HStack(alignment: .top) {
                            Text(NativeCatalog.label(key)).foregroundStyle(Theme.muted)
                            Spacer(minLength: 12)
                            if let url = URL(string: text), url.scheme == "https", url.host != nil {
                                Link("打开链接", destination: url)
                            } else { Text(text).multilineTextAlignment(.trailing).textSelection(.enabled) }
                        }.font(.system(size: 13))
                    } else if let child = object[key] {
                        DisclosureGroup(NativeCatalog.label(key)) { NativeDataView(value: child, depth: depth + 1).padding(.top, 10) }
                            .font(.system(size: 13)).tint(Theme.primary)
                    }
                }
            default: Text(value.text ?? "").font(.system(size: 13)).textSelection(.enabled)
            }
        }
    }
}

struct NativeFieldEditor: View {
    let field: NativeField
    @Binding var value: JSONValue
    var suggestions: [String] = []
    @State private var numberText = ""
    private var text: Binding<String> { Binding(get: { value.rawText }, set: { value = .string($0) }) }
    private var list: Binding<String> { Binding(get: { value.array.map(\.rawText).joined(separator: "\n") }, set: { value = .array($0.components(separatedBy: CharacterSet(charactersIn: "\n,，")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map(JSONValue.string)) }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(field.label + (field.required ? " *" : "")).font(.system(size: 13, weight: .medium))
            if field.kind == "toggle" {
                Toggle(value == .null ? "未设置" : (value.bool == true ? "开启" : "关闭"), isOn: Binding(get: { value.bool ?? false }, set: { value = .bool($0) }))
                    .font(.system(size: 13)).tint(Theme.primary)
            } else if field.kind == "object" {
                ForEach(field.children ?? []) { child in
                    NativeFieldEditor(field: child, value: Binding(get: { value[child.key] }, set: { v in var object = value.object; object[child.key] = v; value = .object(object) }))
                }
            } else if field.kind == "objects" {
                ForEach(Array(value.array.enumerated()), id: \.offset) { index, _ in
                    VStack(spacing: 14) {
                        HStack { Text("\(field.label) \(index + 1)").font(.system(size: 12, weight: .medium)); Spacer(); Button("移除", role: .destructive) { var items = value.array; items.remove(at: index); value = .array(items) }.font(.system(size: 12)) }
                        ForEach(field.children ?? []) { child in
                            NativeFieldEditor(field: child, value: Binding(get: { index < value.array.count ? value.array[index][child.key] : .null }, set: { v in
                                var items = value.array
                                guard index < items.count else { return }
                                var object = items[index].object; object[child.key] = v; items[index] = .object(object); value = .array(items)
                            }))
                        }
                    }.padding(12).panel()
                }
                Button { value = .array(value.array + [.object([:])]) } label: { Label("添加" + field.label, systemImage: "plus") }.buttonStyle(CapsuleButtonStyle())
            } else if let choices = field.choices, !choices.isEmpty {
                Picker(field.label, selection: Binding(get: { value.rawText }, set: { value = field.numeric ? Double($0).map(JSONValue.number) ?? .null : .string($0) })) { Text("请选择").tag(""); ForEach(choices, id: \.self) { Text(choiceLabel($0)).tag($0) } }.tint(Theme.primary)
            } else if field.kind == "list" {
                TextField("每项一行，也可以用逗号分隔", text: list, axis: .vertical).lineLimit(2...5).font(.system(size: 13)).inputStyle()
                if !suggestions.isEmpty {
                    ScrollView(.horizontal) { HStack { ForEach(suggestions, id: \.self) { item in
                        Button { var array = value.array; if array.contains(.string(item)) { array.removeAll { $0 == .string(item) } } else { array.append(.string(item)) }; value = .array(array) } label: { Label(item, systemImage: value.array.contains(.string(item)) ? "checkmark.circle.fill" : "circle") }.buttonStyle(CapsuleButtonStyle())
                    } } }
                }
            } else if field.kind == "secret" {
                SecureField("留空保留原值", text: text).font(.system(size: 13)).inputStyle().privacySensitive()
                    .accessibilityIdentifier("input." + field.key)
            } else if field.kind == "date" {
                DatePicker(field.label, selection: Binding(get: { ISO8601DateFormatter().date(from: value.rawText) ?? Date() }, set: { value = .string(ISO8601DateFormatter().string(from: $0)) }), displayedComponents: [.date,.hourAndMinute]).font(.system(size:13))
                Button(value == .null ? "使用所选时间" : "清除时间") { value = value == .null ? .string(ISO8601DateFormatter().string(from:Date())) : .null }.font(.system(size:12))
            } else if field.kind == "number" {
                TextField("请输入数字", text: Binding(get: { numberText }, set: { numberText = $0; value = $0.isEmpty ? .null : Double($0).map(JSONValue.number) ?? .string($0) }))
                    .keyboardType(.numbersAndPunctuation).font(.system(size: 13)).inputStyle()
                    .accessibilityIdentifier("input." + field.key)
                    .onAppear { numberText = value.rawText }.onChange(of: value) { _, v in if v.rawText != numberText, v.number != nil { numberText = v.rawText } }
                if !suggestions.isEmpty { Menu("选择" + field.label) { ForEach(suggestions, id: \.self) { item in Button(item) { value = Double(item).map(JSONValue.number) ?? .null } } }.font(.system(size: 12)) }
            } else {
                TextField("请输入" + field.label, text: text, axis: .vertical).lineLimit(1...4).font(.system(size: 13)).inputStyle()
                    .accessibilityIdentifier("input." + field.key)
                if !suggestions.isEmpty {
                    Menu("选择" + field.label) { ForEach(suggestions, id: \.self) { item in Button(item) { value = .string(item) } } }.font(.system(size: 12))
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("field." + field.key)
    }
    private func choiceLabel(_ s: String) -> String {
        ["auto":"自动续费","manual":"手动续费","empty":"保持续费","terminateAtExpirationDate":"到期终止","terminateAtEngagementDate":"合同到期终止","STOP_ENGAGEMENT_FALLBACK_DEFAULT_PRICE":"结束合同并恢复标准价格","STOP_ENGAGEMENT_KEEP_PRICE":"结束合同并保留价格","CANCEL_SERVICE":"合同到期销毁服务","REACTIVATE_ENGAGEMENT":"继续合同期","running":"运行中","paused":"暂停","active":"启用","inactive":"停用","inactiveLocked":"锁定停用","hardDiskDrive":"硬盘","memory":"内存","cooling":"散热","sqlite":"磁盘缓存","all":"全部","os":"Windows Server","sqlstd":"SQL Server 标准版","sqlweb":"SQL Server 网页版","ovh-eu":"欧洲","ovh-ca":"加拿大","ovh-us":"美国"][s] ?? s
    }
}

extension View {
    func inputStyle() -> some View {
        textInputAutocapitalization(.never).autocorrectionDisabled().padding(12)
            .background(Theme.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct NativeOperationView: View {
    @EnvironmentObject var store: AppStore
    let operation: NativeOperation
    let context: NativeContext
    var seed: [String: JSONValue] = [:]
    @State private var values: [String: JSONValue] = [:]
    @State private var original: [String: JSONValue] = [:]
    @State private var result: JSONValue = .null
    @State private var notices: [String] = []
    @State private var suggestions: [String: [String]] = [:]
    @State private var error: String?
    @State private var busy = false
    @State private var initialized = false
    @State private var confirming = false
    @State private var typedTarget = ""
    @State private var succeeded = false
    @State private var pairingImage: UIImage?
    @State private var pairingExpires: Date?
    @State private var configLoaded = false
    private var effectiveContext: NativeContext {
        var target = context
        if context.service == nil, let id = values["account_id"]?.text ?? values["accountId"]?.text, let account = store.accounts.first(where: { $0.id == id }) {
            target.account = account.id; target.accountName = account.name
        }
        return target
    }
    private var visibleFields: [NativeField] { operation.fields.filter { context.bindings[$0.key] == nil && $0.key != "confirm" } }
    private var requiresTypedTarget: Bool { !operation.isRead && operation.danger && context.service != nil && ["install","reinstall","terminate","hardware/replace","snapshot/revert"].contains(where: { operation.path.hasSuffix("/" + $0) }) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !operation.isRead {
                    Label(operation.globalTarget ?? effectiveContext.accountName + (context.service.map { " · " + $0 } ?? ""), systemImage: "person.crop.circle").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    if operation.danger { ErrorCard(message: warning) }
                }
                if let error { ErrorCard(message: error) }
                ForEach(notices, id: \.self) { ErrorCard(message: $0) }
                if busy { ProgressView(operation.isRead ? "加载中…" : "提交中…").frame(maxWidth: .infinity) }
                if !visibleFields.isEmpty {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(visibleFields) { field in
                            if ["account_id","accountId","autoOrderAccountId"].contains(field.key) {
                                Picker(field.label, selection: Binding(get: { values[field.key]?.rawText ?? "" }, set: { values[field.key] = .string($0) })) { Text("请选择账户").tag(""); ForEach(store.accounts) { Text($0.name + " · " + $0.zone).tag($0.id) } }.font(.system(size: 13)).tint(Theme.primary)
                            } else if ["zone","ovhSubsidiary","subsidiary"].contains(field.key) {
                                Picker(field.label, selection: Binding(get: { values[field.key]?.rawText ?? "" }, set: { code in values[field.key] = .string(code); if field.key == "zone", let s = NativeCatalog.shared.subsidiaries.first(where: { $0.code == code }) { values["endpoint"] = .string(s.endpoint) } })) {
                                    Text("请选择站点").tag(""); ForEach(subsidiaries(for: field)) { Text($0.label).tag($0.code) }
                                }.font(.system(size: 13)).tint(Theme.primary)
                            } else {
                                NativeFieldEditor(field: field, value: Binding(get: { values[field.key] ?? .null }, set: { values[field.key] = $0 }), suggestions: suggestions[field.key] ?? [])
                            }
                        }
                    }.padding(16).panel().disabled(busy)
                }
                if !operation.isRead || !visibleFields.isEmpty {
                    Button { if operation.isRead { Task { await execute() } } else { do { _ = try operation.resolve(values: effectiveValues, context: context); confirming = true } catch { self.error = error.localizedDescription } } } label: {
                        Label(operation.isRead ? "查询" : operation.title, systemImage: operation.isRead ? "magnifyingglass" : "checkmark").frame(maxWidth: .infinity)
                    }.buttonStyle(CapsuleButtonStyle(solid: true)).disabled(busy || operation.path == "/settings" && !operation.isRead && !configLoaded).accessibilityIdentifier("operation.submit")
                    if operation.path == "/settings", !operation.isRead, !configLoaded { Button("重新读取设置") { initialized = false; Task { await initialize() } }.buttonStyle(CapsuleButtonStyle()) }
                }
                if succeeded { Label(result["message"].text ?? "请求已成功提交", systemImage: "checkmark.circle").font(.system(size: 13)).foregroundStyle(Theme.success) }
                if let pairingImage, let expires = pairingExpires {
                    VStack(spacing: 12) {
                        Image(uiImage: pairingImage).interpolation(.none).resizable().scaledToFit().frame(width: 220, height: 220)
                        Text(result["code"].text ?? "").font(.system(size: 26, weight: .semibold, design: .monospaced))
                        TimelineView(.periodic(from: .now, by: 1)) { c in Text(expires > c.date ? "有效期剩余 \(max(0, Int(expires.timeIntervalSince(c.date)))) 秒" : "配对码已过期，请重新生成").font(.system(size: 12)).foregroundStyle(Theme.muted) }
                    }.frame(maxWidth: .infinity).padding(16).panel()
                } else if result != .null { NativeResourceResults(value: result, operation: operation, context: effectiveContext) }
                if !operation.isRead && succeeded, let service = context.service {
                    let root = operation.scope == "vps" ? "/vps-control" : "/server-control"
                    NativeOperationLink(operation: NativeCatalog.shared.operation(root + "/:service_name/tasks"), context: .init(account: context.account, accountName: context.accountName, service: service))
                }
            }.padding(14).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.page(operation.title, back: true, showAccount: false)
            .nativeRefreshable(scope: operation.id) { if operation.isRead { await execute() } }
            .task { await initialize() }
            .sheet(isPresented: $confirming) { confirmation }
    }
    private var warning: String {
        if operation.path.hasSuffix("/install") || operation.path.hasSuffix("/reinstall") { return "重装会清空系统盘数据，请确认备份、系统模板和分区配置。" }
        if operation.path.hasSuffix("/terminate") { return "立即终止会使服务暂停。这与到期终止不同，请核对目标服务器。" }
        if operation.path.hasSuffix("/hardware/replace") { return "更换硬件会中断服务。仅填写已确认故障的组件；勾选反向选择时将更换未列出的磁盘。" }
        return "此操作会修改或删除当前目标的数据，请核对后确认。"
    }
    private var confirmation: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(operation.title).font(.system(size: 20, weight: .semibold))
                    Text(operation.globalTarget ?? effectiveContext.accountName).font(.system(size: 14))
                    if let service = context.service { Text(service).font(.system(size: 13, design: .monospaced)).textSelection(.enabled) }
                    if operation.danger { ErrorCard(message: warning) }
                    NativeDataView(value: .object(effectiveValues)).padding(14).panel()
                    if requiresTypedTarget {
                        Text("输入完整服务名称以确认").font(.system(size: 13))
                        TextField(context.service ?? "", text: $typedTarget).inputStyle().accessibilityIdentifier("operation.confirmTarget")
                    }
                    Button {
                        confirming = false
                        Task { await execute() }
                    } label: { Text("确认" + operation.title).frame(maxWidth: .infinity) }
                        .buttonStyle(CapsuleButtonStyle(solid: true)).disabled(busy || requiresTypedTarget && typedTarget != context.service).accessibilityIdentifier("operation.confirm")
                }.padding(18)
            }.background(Theme.background).navigationTitle("确认操作").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { confirming = false } } }
        }.presentationDragIndicator(.visible)
    }
    private var effectiveValues: [String: JSONValue] {
        var values = self.values
        if !operation.isRead, operation.fields.contains(where: { $0.key == "confirm" }) { values["confirm"] = .bool(true) }
        if operation.path == "/settings", !operation.isRead { return original.merging(values) { _, new in new } }
        if operation.method == "PUT", !original.isEmpty {
            return values.filter { entry in original[entry.key] != entry.value || operation.fields.first(where: { $0.key == entry.key })?.location == "path" }
        }
        return values
    }
    private func subsidiaries(for field: NativeField) -> [NativeSubsidiary] {
        if field.key == "zone" { return NativeCatalog.shared.subsidiaries }
        let endpoint = NativeCatalog.shared.subsidiaries.first { $0.code == values[field.key]?.rawText }?.endpoint ?? store.accounts.first { $0.id == context.account }?.endpoint
        return NativeCatalog.shared.subsidiaries.filter { $0.endpoint == endpoint }
    }
    private func initialize() async {
        guard !initialized else { return }; initialized = true
        values = seed; original = seed
        for field in operation.fields where field.required && field.kind == "toggle" && values[field.key] == nil { values[field.key] = .bool(false) }
        if operation.fields.contains(where: { $0.key == "account_id" }) { values["account_id"] = .string(context.account) }
        if operation.path == "/settings", !operation.isRead, let connection = store.connection {
            busy = true
            do {
                let r = try await APIClient(connection: connection).value("/settings")
                original = r.value.object; values = original; notices = r.notices; configLoaded = true
            } catch { self.error = error.localizedDescription }
            busy = false
        }
        if operation.path == "/accounts/:id", operation.method == "PUT", let connection = store.connection, let id = context.bindings["id"]?.text {
            busy = true
            do {
                let r = try await APIClient(connection:connection).value("/accounts/" + APIClient.component(id))
                original = r.value.object
                values = original.filter { !["appKey","appSecret","consumerKey"].contains($0.key) }
                notices = r.notices
            } catch { self.error = error.localizedDescription }
            busy = false
        }
        if operation.isRead && visibleFields.isEmpty { await execute() }
        await loadSuggestions()
    }
    private func execute() async {
        guard !busy, let connection = store.connection else { return }
        busy = true; error = nil; succeeded = false
        let session = store.sessionID
        defer { busy = false }
        do {
            let (path, query, body) = try operation.resolve(values: effectiveValues, context: context)
            let response = try await APIClient(connection: connection).value(path, account: effectiveContext.account, method: operation.method, body: body, query: query)
            guard !Task.isCancelled, store.sessionID == session, store.connection == connection else { return }
            result = response.value; notices = response.notices
            for key in ["warning","regionWarning","subsidiaryWarning"] { if let text = result[key].text, !text.isEmpty { notices.append(text) } }
            notices += result["warnings"].array.compactMap(\.text)
            succeeded = !operation.isRead
            if succeeded { store.nativeRevision += 1 }
            if operation.path == "/app/pairing-codes" { makePairingImage() }
            if operation.path.hasPrefix("/accounts"), !operation.isRead { await store.refresh() }
        } catch {
            guard !Task.isCancelled, !APIClient.isCancellation(error), store.sessionID == session, store.connection == connection else { return }
            self.error = error.localizedDescription
            if case PanelError.unauthorized = error { store.invalidate(connection) }
        }
    }
    private func loadSuggestions() async {
        guard let service = context.service, let connection = store.connection else { return }
        let root = (operation.scope == "vps" ? "/vps-control/" : "/server-control/") + APIClient.component(service)
        let paths: [(String, String, String, String)] = [("templateName","/templates","templates","templateName"),("templateId","/templates","templates","id"),("bootId","/boot-mode","bootModes","bootId"),("ip","/ips","ips","ipAddress"),("ipAddress","/ips","ips","ipAddress"),("type","/ipmi-types","supportedTypes","")]
        for (key, suffix, arrayKey, itemKey) in paths where visibleFields.contains(where: { $0.key == key }) {
            do {
                let response = try await APIClient(connection: connection).value(root + suffix, account: context.account)
                let array = response.value[arrayKey].array.isEmpty ? response.value.array : response.value[arrayKey].array
                suggestions[key] = array.compactMap { item in
                    let v = item[itemKey] != .null ? item[itemKey] : item["templateId"] != .null ? item["templateId"] : item["id"] != .null ? item["id"] : item
                    return v == .null ? nil : v.rawText
                }
            } catch { /* Suggestions are optional; the primary form remains available. */ }
        }
    }
    private func makePairingImage() {
        let code = result["code"].text ?? result["pairingCode"].text ?? ""
        guard !code.isEmpty, let address = store.connection?.address else { return }
        let payload = address + "/api/app/pair#" + code
        let qr = CIFilter.qrCodeGenerator()
        qr.message = Data(payload.utf8)
        if let out = qr.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)), let image = CIContext().createCGImage(out, from: out.extent) { pairingImage = UIImage(cgImage: image) }
        pairingExpires = result["expiresAt"].number.map { Date(timeIntervalSince1970:$0) } ?? ISO8601DateFormatter().date(from: result["expiresAt"].rawText) ?? Date().addingTimeInterval(120)
    }
}
