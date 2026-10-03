import SwiftUI
import Charts

struct NativeAssetDetailView: View {
    @EnvironmentObject var store: AppStore
    let asset: Asset
    let accountID: String
    let accountName: String
    @State private var tab = "概览"
    @State private var hideIPs = false
    @StateObject private var detail = AssetDetailStore()
    @StateObject private var snapshot = NativeLoader()
    private var context: NativeContext { .init(account: accountID, accountName: accountName, service: asset.serviceName) }
    private var currentAsset: Asset { store.selectedAccountID == accountID ? store.assets.first { $0.id == asset.id } ?? asset : asset }
    private var operations: [NativeOperation] { NativeCatalog.shared.operations.filter { $0.scope == (asset.kind == .vps ? "vps" : "dedicated") } }
    private var groups: [String] { asset.kind == .vps ? ["概览","电源","快照","高级"] : ["概览","电源","维护","高级"] }
    private var current: [NativeOperation] {
        operations.filter { op in
            if tab == "快照" { return op.path.contains("/snapshot") || op.path.contains("/automated-backup") }
            if asset.kind == .vps && tab == "高级", op.path.contains("/snapshot") || op.path.contains("/automated-backup") { return false }
            return op.group == tab
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(currentAsset.name).font(.system(size: 19, weight: .semibold)); Spacer(); StatusBadge(text: currentAsset.stateLabel, healthy: currentAsset.healthy) }
                    Text(asset.serviceName).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).foregroundStyle(Theme.muted)
                    HStack { Text(asset.specification); Spacer(); Text(asset.location) }.font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Text(accountName).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }.padding(16).panel()
                Picker("管理页签", selection: $tab) { ForEach(groups, id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).accessibilityIdentifier("detail.tabs")
                if tab == "概览" {
                    if let error = detail.error { ErrorCard(message: error) }
                    if detail.loading { ProgressView("同步实例详情…").frame(maxWidth: .infinity) }
                    if !detail.rows.isEmpty {
                        VStack(spacing: 13) { ForEach(Array(detail.rows.enumerated()), id: \.offset) { row in HStack { Text(row.element.0).foregroundStyle(Theme.muted); Spacer(); Text(row.element.1).textSelection(.enabled) }.font(.system(size: 13)); if row.offset < detail.rows.count-1 { Divider() } } }.padding(16).panel()
                    }
                    addresses
                    if asset.kind == .dedicated { NativeTrafficView(context: context) }
                }
                if tab == "快照" {
                    NativeLoadingState(loader: snapshot)
                    if snapshot.value != .null { NativeDataView(value: snapshot.value["snapshot"] == .null ? snapshot.value : snapshot.value["snapshot"]).padding(16).panel() }
                }
                if tab == "高级" { NativeOperationGroups(operations: current, context: context) }
                else { VStack(spacing: 0) {
                    ForEach(Array(current.enumerated()), id: \.element.id) { index, op in
                        NativeOperationLink(operation: op, context: context)
                        if index < current.count - 1 { Divider().padding(.leading, 48) }
                    }
                }.panel() }
                if tab == "概览" && asset.kind == .dedicated {
                    VStack(spacing: 0) {
                        NativeOperationLink(operation: NativeCatalog.shared.operation("PUT", "/server-control/:service_name/alias"), context: context)
                        Divider(); NativeOperationLink(operation: NativeCatalog.shared.operation("DELETE", "/server-control/:service_name/alias"), context: context)
                    }.panel()
                }
            }.padding(14).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }.page(asset.kind.title + "控制", back: true, showAccount: false, titleID: "detail.title")
            .task { await load() }
            .onChange(of: store.nativeRevision) { _,_ in Task { await load(); await loadSnapshot(); await store.refresh(includeAccounts:false) } }
            .nativeRefreshable { await load(); await loadSnapshot() }
            .task(id: tab) { if tab == "快照" { await snapshot.load(asset.kind.apiPath + "/" + APIClient.component(asset.serviceName) + "/snapshot", store: store, account: accountID) } }
    }
    private var addresses: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label("IP 地址", systemImage: "network").font(.system(size: 14, weight: .semibold)); Spacer(); Button(hideIPs ? "显示 IP" : "隐藏 IP") { hideIPs.toggle() }.font(.system(size: 12)).accessibilityIdentifier("detail.hideIPs") }
            let ips = detail.ips.isEmpty ? asset.ip.map { [$0] } ?? [] : detail.ips
            ForEach(ips, id: \.self) { ip in HStack { Text(hideIPs ? "••••••••" : ip).font(.system(size: 12, design: .monospaced)).textSelection(.enabled); Spacer(); if !hideIPs { Button { UIPasteboard.general.string = ip } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel("复制 IP") } } }
            if ips.isEmpty { Text("暂无 IP 信息").font(.system(size: 12)).foregroundStyle(Theme.muted) }
        }.padding(16).panel()
    }
    private func load() async { if let connection = store.connection { await detail.load(asset: asset, connection: connection, account: accountID) } }
    private func loadSnapshot() async { if tab == "快照" { await snapshot.load(asset.kind.apiPath + "/" + APIClient.component(asset.serviceName) + "/snapshot",store:store,account:accountID) } }
}

struct NativeTrafficView: View {
    @EnvironmentObject var store: AppStore
    let context: NativeContext
    @StateObject private var download = NativeLoader()
    @StateObject private var upload = NativeLoader()
    @State private var period = "daily"
    @State private var metric = "traffic"
    @State private var selectedMAC = ""
    @State private var selectedDate: Date?
    private var macs: [String] { download.value["interfaces"].array.compactMap { $0["mac"].text } }
    private var points: [NativeTrafficPoint] {
        [pointsFrom(download.value, direction: "下载"), pointsFrom(upload.value, direction: "上传")].flatMap { $0 }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("流量监控", systemImage: "chart.xyaxis.line").font(.system(size: 14, weight: .semibold))
            HStack { Picker("周期", selection: $period) { Text("过去 1 小时").tag("hourly"); Text("过去 24 小时").tag("daily"); Text("过去 7 天").tag("weekly"); Text("过去 1 月").tag("monthly"); Text("过去 1 年").tag("yearly") }; Spacer(); Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") } }
            Picker("统计类型", selection: $metric) { Text("带宽").tag("traffic"); Text("数据包").tag("packets"); Text("错误").tag("errors") }.pickerStyle(.segmented)
            if !macs.isEmpty { Picker("网卡", selection: $selectedMAC) { Text("选择网卡").tag(""); ForEach(macs, id: \.self) { Text($0).tag($0) } } }
            NativeLoadingState(loader: download)
            if let error = upload.error { ErrorCard(message: "上传数据：" + error) }
            if points.isEmpty && !download.loading { Text("当前网卡暂无数据").font(.system(size: 12)).foregroundStyle(Theme.muted) }
            else {
                ForEach(["下载","上传"], id: \.self) { direction in
                    let values = points.filter { $0.direction == direction }.map(\.value)
                    if !values.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(direction, systemImage: direction == "下载" ? "arrow.down" : "arrow.up").font(.system(size: 12,weight:.medium))
                            HStack {
                                trafficStat("当前", values.last ?? 0)
                                trafficStat("平均", values.reduce(0,+) / Double(values.count))
                                trafficStat("峰值", values.max() ?? 0)
                            }
                        }.padding(10).background(Theme.secondary,in:RoundedRectangle(cornerRadius:10))
                    }
                }
                Chart {
                    ForEach(points) { point in LineMark(x: .value("时间", point.date), y: .value(metric == "traffic" ? "Mbps" : "数值", point.value)).foregroundStyle(by: .value("方向", point.direction)) }
                    if let selectedDate { RuleMark(x: .value("选中时间", selectedDate)).foregroundStyle(Theme.muted.opacity(0.4)) }
                }.chartXSelection(value: $selectedDate)
                    .chartGesture { proxy in SpatialTapGesture().onEnded { value in proxy.selectXValue(at: value.location.x) } }
                    .chartForegroundStyleScale(["下载":Theme.success,"上传":Theme.primary]).frame(height: 180).accessibilityIdentifier("traffic.chart")
                if let selectedDate {
                    Text(selectedDate.formatted(date: .abbreviated,time:.shortened)).font(.system(size:11)).foregroundStyle(Theme.muted)
                    HStack { ForEach(["下载","上传"], id: \.self) { direction in
                        if let point = points.filter({ $0.direction == direction }).min(by: { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }) { Text(direction + " " + formatted(point.value)).font(.system(size:11)) }
                    } }
                }
                HStack { Text(metric == "traffic" ? "Mbps" : "数据点数值"); Spacer(); Text("\(points.count) 个数据点") }.font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }.padding(16).panel().task(id: period + metric) { await load() }
    }
    private func formatted(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) + (metric == "traffic" ? " Mbps" : "") }
    private func trafficStat(_ title: String, _ value: Double) -> some View {
        VStack(alignment:.leading,spacing:4) { Text(title).foregroundStyle(Theme.muted); Text(formatted(value)).monospacedDigit() }.font(.system(size:11)).frame(maxWidth:.infinity,alignment:.leading)
    }
    private func pointsFrom(_ value: JSONValue, direction: String) -> [NativeTrafficPoint] {
        let mac = selectedMAC.isEmpty ? macs.first ?? "" : selectedMAC
        return NativeTrafficPoint.decode(value, mac:mac, metric:metric, direction:direction)
    }
    private func load() async {
        guard let service = context.service else { return }
        let path = "/server-control/" + APIClient.component(service) + "/mrtg"
        async let d: () = download.load(path, store: store, account: context.account, query: ["period":period,"type":metric + ":download"])
        async let u: () = upload.load(path, store: store, account: context.account, query: ["period":period,"type":metric + ":upload"])
        _ = await (d,u)
        if !macs.contains(selectedMAC) { selectedMAC = macs.first ?? "" }
    }
}

struct NativeTrafficPoint: Identifiable {
    let date: Date
    let value: Double
    let direction: String
    var id: String { direction + String(date.timeIntervalSince1970) }
    static func decode(_ value: JSONValue, mac: String, metric: String, direction: String) -> [Self] {
        let nic = value["interfaces"].array.first { $0["mac"].rawText == mac }
        let formatter = ISO8601DateFormatter()
        return (nic?["data"].array ?? []).compactMap { item in
            let timestamp = item["timestamp"].number ?? item["date"].number
            let date = timestamp.map { Date(timeIntervalSince1970: $0) } ?? formatter.date(from:item["timestamp"].rawText) ?? formatter.date(from:item["date"].rawText)
            guard let date, let v = item["value"]["value"].number ?? item["value"].number, v.isFinite else { return nil }
            return Self(date:date,value:metric == "traffic" ? v / 1_000_000 : v,direction:direction)
        }.sorted { $0.date < $1.date }
    }
}

enum NativeRecordKind { case history, logs }
struct NativeRecordsView: View {
    @EnvironmentObject var store: AppStore
    let kind: NativeRecordKind
    @StateObject private var loader = NativeLoader()
    @State private var search = ""
    @State private var filter = "全部"
    @State private var allAccounts = true
    @State private var limit = 100
    private var path: String { kind == .logs ? "/logs" : "/purchase-history" }
    private var rows: [JSONValue] { loader.value.array.reversed().filter { item in
        let text = kind == .logs ? item["message"].rawText + item["source"].rawText : item["planCode"].rawText + item["datacenter"].rawText + item["orderId"].rawText
        return (search.isEmpty || text.localizedCaseInsensitiveContains(search)) && (filter == "全部" || item[kind == .logs ? "level" : "status"].rawText == filter) && (kind == .logs || allAccounts || item["accountId"].rawText == store.selectedAccountID)
    } }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                TextField(kind == .logs ? "搜索日志内容或来源" : "搜索机型、订单或机房", text: $search).inputStyle()
                HStack {
                    Picker(kind == .logs ? "级别" : "状态", selection: $filter) { Text("全部").tag("全部"); if kind == .logs { ForEach(["INFO","WARNING","ERROR","DEBUG"], id: \.self) { Text($0).tag($0) } } else { Text("成功").tag("success"); Text("失败").tag("failed") } }
                    Spacer(); if kind == .history { Toggle("全部账户", isOn: $allAccounts).font(.system(size: 12)).tint(Theme.primary).fixedSize() }
                }
                NativeLoadingState(loader: loader)
                if rows.isEmpty && !loader.loading { NativeEmptyView(title: kind == .logs ? "暂无日志" : "暂无抢购记录", symbol: kind == .logs ? "doc.text" : "clock") }
                ForEach(Array(rows.prefix(limit).enumerated()), id: \.offset) { row in
                    NavigationLink { NativeRecordDetailView(item: row.element, kind: kind) } label: { recordCard(row.element) }.buttonStyle(.plain)
                }
                if rows.count > limit { Button("加载更多（剩余 \(rows.count-limit) 条）") { limit += 100 }.buttonStyle(CapsuleButtonStyle()) }
                NativeOperationLink(operation: NativeCatalog.shared.operation("POST", kind == .logs ? "/logs/flush" : "/purchase-history/refresh-status"), context: store.nativeContext).panel()
                NativeOperationLink(operation: NativeCatalog.shared.operation("DELETE", path), context: store.nativeContext).panel()
            }.padding(14).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }.page(kind == .logs ? "详细日志" : "抢购历史", back: true).task { await load() }.nativeRefreshable { await load() }
            .onChange(of: store.nativeRevision) { _,_ in Task { await load() } }
    }
    private func recordCard(_ item: JSONValue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(kind == .logs ? item["level"].rawText : item["planCode"].rawText).font(.system(size: 14, weight: .semibold)); Spacer(); Text(String(item[kind == .logs ? "timestamp" : "purchaseTime"].rawText.prefix(19))).font(.system(size: 10)).foregroundStyle(Theme.muted) }
            if kind == .logs { Text(item["message"].rawText).font(.system(size: 12)).lineLimit(4).foregroundStyle(Theme.muted) }
            else { HStack { Text(item["datacenter"].rawText.uppercased()); Spacer(); StatusBadge(text: item["status"].rawText == "success" ? "下单成功" : "下单失败", healthy: item["status"].rawText == "success") }.font(.system(size: 12)); if let status = item["orderStatus"].text { Text("付款状态：" + status).font(.system(size: 11)).foregroundStyle(Theme.muted) } }
        }.padding(16).panel()
    }
    private func load() async { await loader.load(path, store: store) }
}

struct NativeRecordDetailView: View {
    let item: JSONValue
    let kind: NativeRecordKind
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) { NativeDataView(value: item).padding(16).panel(); ShareLink(item: item["message"].text ?? item["orderUrl"].text ?? item["planCode"].rawText) { Label("分享", systemImage: "square.and.arrow.up") }.buttonStyle(CapsuleButtonStyle()) }.padding(14) }.page(kind == .logs ? "日志详情" : "订单详情", back: true, showAccount: false)
    }
}

struct NativeMoreView: View {
    @EnvironmentObject var store: AppStore
    private let groups: [(String,[(String,String,String)])] = [
        ("抢购",[("服务器库存","/servers","shippingbox")]),
        ("账户",[("账户管理","/account","person.crop.circle")]),
        ("记录",[("抢购历史","/history","clock.arrow.circlepath"),("详细日志","/logs","doc.text")]),
        ("设置",[("API 设置","/settings","slider.horizontal.3"),("连接与设备","/connection","iphone")])
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(groups, id: \.0) { group, rows in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        VStack(spacing: 0) { ForEach(rows, id: \.1) { title,path,symbol in NavigationLink { NativeDestinationView(destination: .init(path:path,title:title)) } label: { HStack { Image(systemName: symbol).frame(width: 24).foregroundStyle(Theme.muted); Text(title).font(.system(size: 14)); Spacer(); Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.muted) }.padding(16).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("more." + path.dropFirst()); if path != rows.last?.1 { Divider().padding(.leading, 50) } } }.panel()
                    }
                }
            }.padding(14).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.page("更多")
    }
}

struct NativeAccountView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var loader = NativeLoader()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NativeLoadingState(loader: loader)
                if loader.value != .null { NativeDataView(value: loader.value).padding(16).panel() }
                VStack(spacing: 0) {
                    ForEach(NativeCatalog.shared.operations.filter { $0.group == "账户管理" && $0.path != "/ovh/account/info" }) { op in NativeOperationLink(operation: op, context: store.nativeContext); Divider().padding(.leading, 48) }
                }.panel()
            }.padding(14).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.page("账户管理", back: true).task(id: store.selectedAccountID) { await load() }.nativeRefreshable { await load() }
            .onChange(of: store.nativeRevision) { _,_ in Task { await load() } }
    }
    private func load() async { await loader.load("/ovh/account/info", store: store, account: store.selectedAccountID) }
}

struct NativeSettingsView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("nativeAppearance") private var appearance = "system"
    private let categories = ["OVH 账户","抢购","通知通道","App 配对","缓存管理","后端系统","API 设置"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(title: "访问与外观", subtitle: "连接当前自建面板")
                VStack(spacing: 0) {
                    NavigationLink { SettingsView() } label: { HStack { Label("访问密码与连接", systemImage: "key"); Spacer(); Image(systemName: "chevron.right") }.font(.system(size: 14)).padding(14).contentShape(Rectangle()) }.buttonStyle(.plain)
                    Divider()
                    Picker("外观", selection: $appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }.font(.system(size: 13)).padding(14)
                }.panel()
                SectionHeading(title: "OVH 账户", subtitle: "EU、CA、US 的凭据和库存分别管理")
                ForEach(store.accounts) { account in NativeAccountSettingsCard(account: account) }
                NativeOperationLink(operation: NativeCatalog.shared.operation("POST", "/accounts"), context: store.nativeContext).panel()
                SectionHeading(title: "抢购与通知", subtitle: "后端设置会与网页共用")
                NativeOperationLink(operation: NativeCatalog.shared.operation("POST", "/settings"), context: store.nativeContext).panel()
                ForEach(categories.filter { $0 != "OVH 账户" && $0 != "抢购" }, id: \.self) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group).font(.system(size: 13, weight: .semibold))
                        VStack(spacing: 0) {
                            ForEach(NativeCatalog.shared.operations.filter { $0.scope == "panel" && $0.group == group && !$0.path.contains(":") && $0.path != "/settings" }) { op in NativeOperationLink(operation: op, context: store.nativeContext); Divider().padding(.leading, 48) }
                        }.panel()
                    }
                }
                NavigationLink { NativeDevicesView() } label: { Label("管理已配对设备", systemImage: "iphone").frame(maxWidth: .infinity) }.buttonStyle(CapsuleButtonStyle())
            }.padding(14).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.page("API 设置", back: true)
    }
}

struct NativeAccountSettingsCard: View {
    @EnvironmentObject var store: AppStore
    let account: OVHAccount
    private var context: NativeContext { .init(account: account.id, accountName: account.name, bindings: ["id":.string(account.id)]) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(account.name).font(.system(size: 15, weight: .semibold)); Spacer(); Text(account.endpoint + " · " + account.zone).font(.system(size: 11)).foregroundStyle(Theme.muted) }
            if account.isDefault { StatusBadge(text: "默认账户", healthy: true) }
            VStack(spacing: 0) { ForEach(NativeCatalog.shared.operations.filter { $0.path.hasPrefix("/accounts/:id") }) { op in NativeOperationLink(operation: op, context: context, seed: op.method == "PUT" ? ["name":.string(account.name),"endpoint":.string(account.endpoint),"zone":.string(account.zone)] : [:]); Divider().padding(.leading, 48) } }
        }.padding(14).panel()
    }
}

struct NativeDevicesView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var loader = NativeLoader()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                NativeLoadingState(loader: loader)
                ForEach(Array(loader.value["devices"].array.enumerated()), id: \.offset) { item in
                    VStack(alignment: .leading, spacing: 14) {
                        NativeDataView(value: item.element)
                        NativeOperationLink(operation: NativeCatalog.shared.operation("DELETE", "/app/devices/:id"), context: .init(account: store.selectedAccountID, accountName: store.activeAccount?.name ?? "", bindings: ["id":item.element["id"]]))
                    }.padding(16).panel()
                }
                if loader.value["devices"].array.isEmpty && !loader.loading { NativeEmptyView(title: "还没有配对设备", symbol: "iphone") }
                NativeOperationLink(operation: NativeCatalog.shared.operation("POST", "/app/pairing-codes"), context: store.nativeContext).panel()
            }.padding(14)
        }.page("App 配对", back: true).task { await loader.load("/app/devices", store: store) }.nativeRefreshable { await loader.load("/app/devices", store: store) }
            .onChange(of: store.nativeRevision) { _,_ in Task { await loader.load("/app/devices",store:store) } }
    }
}
