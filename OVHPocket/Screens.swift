import SwiftUI

enum Theme {
    private static func neutral(_ light: CGFloat, _ dark: CGFloat) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: dark, alpha: 1) : UIColor(white: light, alpha: 1) })
    }
    static let background = neutral(1, 0.06)
    static let card = neutral(1, 0.08)
    static let secondary = neutral(0.96, 0.14)
    static let border = neutral(0.90, 0.18)
    static let primary = neutral(0.09, 0.96)
    static let onPrimary = neutral(0.98, 0.09)
    static let muted = neutral(0.45, 0.60)
    static let success = Color(red: 0.13, green: 0.77, blue: 0.37)
    static let warning = Color(red: 0.96, green: 0.62, blue: 0.04)
}

struct RootView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        Group {
            if store.connection == nil { ConnectView() }
            else {
                VStack(spacing: 0) {
                    TabView(selection: $store.selectedTab) {
                        ForEach(0..<5, id: \.self) { index in
                            NavigationStack(path: $store.navigationPaths[index]) {
                                NativeTabRoot(index: index)
                                    .navigationDestination(for: ConsoleDestination.self) { NativeDestinationView(destination: $0) }
                            }
                            .toolbar(.hidden, for: .tabBar).tag(index)
                        }
                    }.toolbar(.hidden, for: .tabBar)
                    AppBottomBar()
                }
                    .sheet(isPresented: $store.showPairing) { PairingView(canDismiss: true).environmentObject(store) }
            }
        }.background(Theme.background).foregroundStyle(Theme.primary)
    }
}

struct NativeTabRoot: View {
    let index: Int
    var body: some View {
        switch index {
        case 1: AssetsView()
        case 2: NativeQueueView()
        case 3: NativeMonitorView()
        case 4: NativeMoreView()
        default: OverviewView()
        }
    }
}

struct AppBottomBar: View {
    @EnvironmentObject var store: AppStore
    private let labels = ["仪表盘", "服务器", "队列", "监控", "更多"]
    private let icons = ["chart.bar", "server.rack", "list.clipboard", "bell", "ellipsis"]
    private let identifiers = ["overview", "servers", "queue", "monitor", "more"]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
                Button { store.selectedTab = index } label: {
                    VStack(spacing: 4) {
                        Image(systemName: icons[index]).font(.system(size: 20, weight: store.selectedTab == index ? .semibold : .regular))
                        Text(labels[index]).font(.system(size: 11, weight: store.selectedTab == index ? .semibold : .regular))
                    }.foregroundStyle(store.selectedTab == index ? Theme.primary : Theme.muted)
                        .frame(maxWidth: .infinity).frame(height: 54).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("tab." + identifiers[index])
                    .accessibilityLabel(labels[index]).accessibilityAddTraits(store.selectedTab == index ? .isSelected : [])
            }
        }.background(Theme.background.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 0.5) }
    }
}

struct PageHeader: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var back = false
    var showAccount = true
    var titleID = "page.title"
    var body: some View {
        HStack(spacing: 10) {
            if back {
                Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 17, weight: .medium)).frame(width: 32, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("返回").accessibilityIdentifier("navigation.back")
            }
            Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier(titleID)
            Spacer(minLength: 4)
            if showAccount { AccountMenu() }
        }.padding(.horizontal, 14).frame(minHeight: 52).background(Theme.background)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 0.5) }
    }
}

extension View {
    func panel() -> some View {
        background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border, lineWidth: 1).allowsHitTesting(false) }
    }
    func page(_ title: String, back: Bool = false, showAccount: Bool = true, titleID: String = "page.title") -> some View {
        background(Theme.background).toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { PageHeader(title: title, back: back, showAccount: showAccount, titleID: titleID) }
    }
}

struct CapsuleButtonStyle: ButtonStyle {
    var solid = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium)).padding(.horizontal, 15).frame(minHeight: 40)
            .foregroundStyle(solid ? Theme.onPrimary : Theme.primary)
            .background(solid ? Theme.primary : configuration.isPressed ? Theme.secondary : Theme.card, in: Capsule())
            .overlay { Capsule().strokeBorder(solid ? Color.clear : Theme.border, lineWidth: 1).allowsHitTesting(false) }
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct ConnectView: View {
    var body: some View { PairingView() }
}

struct LegacyConnectForm: View {
    @EnvironmentObject var store: AppStore
    @State private var address = ""
    @State private var key = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "shield").font(.system(size: 28, weight: .medium)).foregroundStyle(Theme.onPrimary)
                        .frame(width: 58, height: 58).background(Theme.primary, in: RoundedRectangle(cornerRadius: 12))
                    Text("OVH 控制台").font(.system(size: 28, weight: .bold))
                    Text("连接自己的面板，管理 OVH 账户和服务器。").font(.system(size: 14)).foregroundStyle(Theme.muted)
                }.padding(.top, 34)
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("面板地址").font(.system(size: 13, weight: .medium))
                        TextField("https://你的面板域名", text: $address).textContentType(.URL).keyboardType(.URL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("connection.address")
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 9) {
                        Text("面板访问密钥").font(.system(size: 13, weight: .medium))
                        SecureField("输入面板的访问密钥", text: $key).textContentType(.password)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().accessibilityIdentifier("connection.key")
                    }
                }.font(.system(size: 15)).padding(18).panel()
                if let error = store.error { ErrorCard(message: error) }
                Button {
                    Task { await store.connect(address: address, key: key); if store.connection != nil { key = "" } }
                } label: {
                    HStack { if store.connecting { ProgressView().tint(Theme.onPrimary) }; Text(store.connecting ? "正在连接…" : "连接面板"); Spacer(); Image(systemName: "arrow.right") }
                }.buttonStyle(CapsuleButtonStyle(solid: true)).disabled(store.connecting).accessibilityIdentifier("connection.submit")
                Label("密钥保存在本机钥匙串", systemImage: "lock.shield").font(.system(size: 12)).foregroundStyle(Theme.muted)
                Text("填写面板访问密钥即可。OVH 的账户密钥由现有面板管理。").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }.padding(22).frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Theme.background).scrollDismissesKeyboard(.interactively)
            .onAppear { if let connection = store.connection { address = connection.address } }
    }
}

struct AccountMenu: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        Menu {
            ForEach(store.accounts) { account in
                Button { store.selectAccount(account.id) } label: {
                    Label(account.name + " · " + account.zone, systemImage: account.id == store.selectedAccountID ? "checkmark" : "person.crop.circle")
                }.accessibilityIdentifier("account." + account.region)
            }
        } label: {
            HStack(spacing: 7) {
                Text(store.activeAccount?.name ?? "选择账户").font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(store.activeAccount?.zone ?? "OVH").font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 3).background(Theme.card, in: RoundedRectangle(cornerRadius: 4))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted)
            }.padding(.horizontal, 10).frame(height: 36).frame(maxWidth: 235)
                .background(Theme.secondary, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityIdentifier("account.menu").accessibilityLabel("切换 OVH 账户")
    }
}

struct OverviewView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    private var metricsPollingSession: UUID? { store.selectedTab == 0 && scenePhase == .active ? store.sessionID : nil }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("OVH 服务器抢购平台状态概览").font(.system(size: 12)).foregroundStyle(Theme.muted)
                if let error = store.error { ErrorCard(message: error, retry: { Task { await store.refresh() } }) }
                HStack(alignment: .top, spacing: 8) {
                    MetricCard(title: "活跃队列", value: store.stats.map { "\($0.activeQueues)" } ?? "—", symbol: "list.clipboard")
                    MetricCard(title: "服务器总数", value: store.stats.map { "\($0.totalServers)" } ?? "—", symbol: "server.rack", footnote: store.stats.map { "可用 \($0.availableServers)" })
                    MetricCard(title: "下单成功", value: store.stats.map { "\($0.purchaseSuccess)" } ?? "—", symbol: "checkmark.circle", footnote: "待付款")
                }
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Label("当前账户实例", systemImage: "server.rack").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button("查看实例") { store.selectedTab = 1 }.font(.system(size: 12)).buttonStyle(.plain).accessibilityIdentifier("overview.instances")
                    }
                    Text(store.activeAccount?.name ?? "请选择账户").font(.system(size: 15, weight: .semibold)).accessibilityIdentifier("overview.account")
                    HStack {
                        Text(store.loading && store.refreshedAt == nil ? "同步中…" : "\(store.serverCount) 台独立服务器 · \(store.vpsCount) 台 VPS")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        Spacer()
                        StatusBadge(text: store.loading ? "同步中" : store.error == nil ? "已同步" : "部分失败", healthy: !store.loading && store.error == nil)
                    }
                }.padding(16).panel()
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Label("活跃队列", systemImage: "list.clipboard").font(.system(size: 14, weight: .semibold)); Spacer(); NavigationLink("查看全部") { NativeQueueView(back:true) }.font(.system(size: 12)).foregroundStyle(Theme.muted).buttonStyle(.plain) }
                    if store.accountQueue.isEmpty {
                        VStack(spacing: 11) {
                            Image(systemName: "calendar").font(.system(size: 27, weight: .light)).foregroundStyle(Theme.muted)
                            Text("暂无活跃任务").font(.system(size: 13)).foregroundStyle(Theme.muted)
                            NavigationLink { NativeServersView(back:true) } label: { Label("创建抢购任务", systemImage: "plus") }
                                .buttonStyle(CapsuleButtonStyle(solid: true))
                        }.frame(maxWidth: .infinity).padding(.vertical, 10)
                    } else {
                        ForEach(store.accountQueue.prefix(4)) { item in
                            HStack { VStack(alignment: .leading, spacing: 5) { Text(item.planCode).font(.system(size: 13, weight: .medium)); Text(item.datacenter.uppercased()).font(.system(size: 11)).foregroundStyle(Theme.muted) }; Spacer(); Text(item.statusLabel).font(.system(size: 11)) }
                        }
                    }
                }.padding(16).panel()
                SystemResourcesView()
                VStack(alignment: .leading, spacing: 14) {
                    Label("系统状态", systemImage: "checkmark.circle").font(.system(size: 14, weight: .semibold))
                    StatusRow(title: "API 连接", value: store.stats == nil ? "未连接" : "已连接", active: store.stats != nil)
                    Divider()
                    StatusRow(title: "抢购处理器", value: store.stats?.queueProcessorRunning.map { $0 ? "运行中" : "未运行" } ?? "未知", active: store.stats?.queueProcessorRunning == true)
                    Divider()
                    StatusRow(title: "服务器监控", value: store.stats?.monitorRunning.map { $0 ? "运行中" : "待启用" } ?? "未知", active: store.stats?.monitorRunning == true)
                }.padding(16).panel()
                HStack(spacing: 10) {
                    Button { store.selectedTab = 1 } label: { Label("我的实例", systemImage: "server.rack").frame(maxWidth: .infinity) }.buttonStyle(CapsuleButtonStyle())
                    NavigationLink { NativeServersView(back:true) } label: { Label("服务器库存", systemImage: "shippingbox").frame(maxWidth: .infinity) }.buttonStyle(CapsuleButtonStyle())
                }
                SectionHeading(title: "账户", subtitle: "\(store.accounts.count) 个账户 · 机型、价格和库存按当前账户显示")
                VStack(spacing: 0) {
                    ForEach(Array(store.accounts.enumerated()), id: \.element.id) { index, account in
                        Button { store.selectAccount(account.id) } label: {
                            HStack(spacing: 12) {
                                Text(account.zone).font(.system(size: 11, weight: .semibold)).frame(width: 34, height: 32).background(Theme.secondary, in: RoundedRectangle(cornerRadius: 7))
                                VStack(alignment: .leading, spacing: 4) { Text(account.name).font(.system(size: 13, weight: .medium)); Text(account.regionName + " · " + account.currency).font(.system(size: 11)).foregroundStyle(Theme.muted) }
                                Spacer()
                                Image(systemName: account.id == store.selectedAccountID ? "checkmark" : "chevron.right").font(.system(size: 13)).foregroundStyle(Theme.muted)
                            }.padding(14).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("overview.select." + account.region)
                        if index < store.accounts.count - 1 { Divider().padding(.leading, 14) }
                    }
                }.panel()
                if let date = store.refreshedAt { Text("最后同步 " + date.formatted(date: .omitted, time: .shortened)).font(.system(size: 11)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).accessibilityIdentifier("overview.synced") }
            }.padding(14).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.page("仪表盘").nativeRefreshable {
            async let overview: Void = store.refresh()
            async let metrics: Void = store.refreshSystemMetrics()
            _ = await (overview, metrics)
        }.task(id: metricsPollingSession) {
            guard metricsPollingSession != nil else { return }
            while !Task.isCancelled {
                await store.refreshSystemMetrics()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
}

struct SystemResourcesView: View {
    @EnvironmentObject var store: AppStore
    private var unknown: String { store.metricsError == nil ? "读取中…" : "读取失败" }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("系统资源").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("面板服务器").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            HStack(alignment: .top, spacing: 8) {
                ResourceMetricCard(id: "cpu", title: "CPU", subtitle: store.systemMetrics.map { "\($0.cpu.cores) 核心" }, percent: store.systemMetrics?.cpu.usage, unknown: unknown)
                ResourceMetricCard(id: "memory", title: "内存", subtitle: store.systemMetrics.map { SystemMetrics.bytes($0.memory.usedBytes) + " / " + SystemMetrics.bytes($0.memory.totalBytes) }, percent: store.systemMetrics?.memory.usage, unknown: unknown)
                ResourceMetricCard(id: "disk", title: "存储", subtitle: store.systemMetrics.map { SystemMetrics.bytes($0.disk.usedBytes) + " / " + SystemMetrics.bytes($0.disk.totalBytes) }, percent: store.systemMetrics?.disk.usage, unknown: unknown)
            }
            if let error = store.metricsError {
                HStack(alignment: .top, spacing: 8) {
                    Text("资源读取失败：" + error).font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Spacer(minLength: 0)
                    Button("重试") { Task { await store.refreshSystemMetrics() } }.font(.system(size: 12)).buttonStyle(.plain)
                        .accessibilityIdentifier("metrics.retry")
                }
            }
        }
    }
}

struct ResourceMetricCard: View {
    let id: String
    let title: String
    let subtitle: String?
    let percent: Double?
    let unknown: String
    private var tone: Color {
        guard let percent else { return Theme.muted }
        switch ResourceTone(percent: percent) {
        case .normal: return Theme.success
        case .warning: return Theme.warning
        case .critical: return .red
        }
    }
    private var detail: String { percent == nil ? subtitle == nil ? unknown : "暂无读数" : subtitle ?? "—" }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                description(alignment: .leading, font: 14)
                Spacer(minLength: 0)
                ring(size: 96)
            }.frame(minWidth: 230).padding(.horizontal, 14).padding(.vertical, 16)
            VStack(spacing: 6) {
                ring(size: 68)
                description(alignment: .center, font: 12)
            }.frame(maxWidth: .infinity).padding(.horizontal, 8).padding(.vertical, 12)
        }.frame(maxWidth: .infinity).panel()
            .accessibilityElement(children: .ignore).accessibilityIdentifier("metrics." + id)
            .accessibilityLabel(title).accessibilityValue((percent.map { "\(Int($0.rounded()))%" } ?? "—") + "，" + detail)
    }
    private func description(alignment: HorizontalAlignment, font: CGFloat) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.muted)
            Text(detail).font(.system(size: font, weight: .semibold)).monospacedDigit()
                .foregroundStyle(tone).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
    private func ring(size: CGFloat) -> some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75).stroke(Theme.border, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(135))
            if let percent, percent > 0 {
                Circle().trim(from: 0, to: 0.75 * percent / 100).stroke(tone, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(135))
            }
            Text(percent.map { "\(Int($0.rounded()))%" } ?? "—").font(.system(size: 20, weight: .semibold)).monospacedDigit().foregroundStyle(tone)
        }.padding(4).frame(width: size, height: size)
    }
}

struct AssetsView: View {
    @EnvironmentObject var store: AppStore
    @State private var filter = "all"
    @State private var search = ""
    var back: Bool
    init(kind: AssetKind? = nil, back: Bool = false) { _filter = State(initialValue: kind?.rawValue ?? "all"); self.back = back }
    var filtered: [Asset] { store.assets.filter { (filter == "all" || $0.kind.rawValue == filter) && (search.isEmpty || ($0.name + $0.serviceName + $0.location).localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text("管理已购独立服务器和 VPS").font(.system(size: 12)).foregroundStyle(Theme.muted); Spacer(); Button { Task { await store.refresh() } } label: { Label("刷新", systemImage: "arrow.clockwise") }.buttonStyle(CapsuleButtonStyle()).disabled(store.loading).accessibilityIdentifier("assets.refresh") }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("搜索名称、机房或服务编号", text: $search).font(.system(size: 14)).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("assets.search")
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }.accessibilityLabel("清除搜索").accessibilityIdentifier("assets.clearSearch") }
                }.padding(.horizontal, 14).frame(height: 44).background(Theme.card, in: Capsule()).overlay { Capsule().strokeBorder(Theme.border, lineWidth: 1).allowsHitTesting(false) }
                HStack(spacing: 4) {
                    FilterButton(title: "全部", value: "all", selected: $filter)
                    FilterButton(title: "独立服务器", value: "dedicated", selected: $filter)
                    FilterButton(title: "VPS", value: "vps", selected: $filter)
                }.padding(4).background(Theme.secondary, in: Capsule())
                if let error = store.error { ErrorCard(message: error, retry: { Task { await store.refresh() } }) }
                if store.loading && store.assets.isEmpty { ProgressView("正在获取服务器…").font(.system(size: 13)).frame(maxWidth: .infinity).padding(.top, 40) }
                else if filtered.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "server.rack").font(.system(size: 30, weight: .light)).foregroundStyle(Theme.muted)
                        Text(search.isEmpty ? "暂无实例" : "未找到服务器").font(.system(size: 15, weight: .medium))
                        Text(search.isEmpty ? "当前账户没有返回此类型的已购实例。" : "试试其他名称或机房。").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }.frame(maxWidth: .infinity).padding(.vertical, 36).panel()
                } else {
                    ForEach(filtered) { asset in
                        NavigationLink { NativeAssetDetailView(asset: asset, accountID: store.selectedAccountID, accountName: store.activeAccount?.name ?? "") } label: { AssetCard(asset: asset) }
                            .buttonStyle(.plain).accessibilityIdentifier("asset." + asset.serviceName)
                    }
                }
            }.padding(14).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.page("服务器实例", back: back).nativeRefreshable { await store.refresh() }
            .task { await store.refresh(includeAccounts: false) }
            .navigationDestination(for: AssetRoute.self) { route in
                NativeAssetDetailView(asset: route.asset, accountID: route.accountID, accountName: route.accountName)
            }
    }
}

struct FilterButton: View {
    let title: String
    let value: String
    @Binding var selected: String
    var body: some View {
        Button { selected = value } label: {
            Text(title).font(.system(size: 12, weight: selected == value ? .medium : .regular)).frame(maxWidth: .infinity).frame(minHeight: 36)
                .foregroundStyle(selected == value ? Theme.primary : Theme.muted)
                .background(selected == value ? Theme.card : Color.clear, in: Capsule())
                .overlay { Capsule().strokeBorder(selected == value ? Theme.border : Color.clear, lineWidth: 1) }
        }.buttonStyle(.plain).accessibilityIdentifier("assets.filter." + value).accessibilityAddTraits(selected == value ? .isSelected : [])
    }
}

struct AssetCard: View {
    let asset: Asset
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: asset.kind.symbol).font(.system(size: 20, weight: .regular)).frame(width: 38, height: 38).background(Theme.secondary, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 4) { Text(asset.name).font(.system(size: 16, weight: .semibold)).lineLimit(2); Text(asset.kind.title + " · " + asset.location).font(.system(size: 11)).foregroundStyle(Theme.muted) }
                Spacer(minLength: 3)
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            Text(asset.specification).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(2)
            HStack { StatusBadge(text: asset.stateLabel, healthy: asset.healthy); Spacer(); Text(asset.renewal.map { $0 ? "自动续费" : "手动续费" } ?? "续费信息未知").font(.system(size: 11)).foregroundStyle(Theme.muted) }
            if let issue = asset.issue { Label(issue, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(Theme.warning) }
        }.padding(16).panel()
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var signingOut = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "连接", subtitle: "当前使用的自建 OVH 面板")
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("面板").foregroundStyle(Theme.muted); Spacer(); Text(store.connection?.url.host ?? "") }.font(.system(size: 13))
                    Divider()
                    Label(store.connection?.authentication == .deviceToken ? "设备令牌已存入钥匙串" : "访问密钥已存入钥匙串", systemImage: "lock.shield").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    if let deviceID = store.connection?.deviceID { Text("已配对设备 · #\(deviceID)").font(.system(size: 12)).foregroundStyle(Theme.muted).accessibilityIdentifier("settings.deviceID") }
                    Button { Task { await store.reconnect() } } label: { Label("刷新账户与实例", systemImage: "arrow.clockwise") }.buttonStyle(CapsuleButtonStyle()).accessibilityIdentifier("settings.refresh")
                    Button { store.error = nil; store.showPairing = true } label: { Label(store.connection?.authentication == .deviceToken ? "重新配对" : "改用扫码配对", systemImage: "qrcode.viewfinder") }.buttonStyle(CapsuleButtonStyle()).accessibilityIdentifier("settings.pair")
                }.padding(16).panel()
                SectionHeading(title: "OVH 账户", subtitle: "\(store.accounts.count) 个账户")
                VStack(spacing: 0) {
                    ForEach(Array(store.accounts.enumerated()), id: \.element.id) { index, account in
                        Button { store.selectAccount(account.id) } label: {
                            HStack { VStack(alignment: .leading, spacing: 4) { Text(account.name).font(.system(size: 13, weight: .medium)); Text(account.regionName + " · " + account.zone).font(.system(size: 11)).foregroundStyle(Theme.muted) }; Spacer(); if account.id == store.selectedAccountID { Image(systemName: "checkmark").font(.system(size: 13)) } }.padding(14).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if index < store.accounts.count - 1 { Divider().padding(.leading, 14) }
                    }
                }.panel()
                NavigationLink { NativeSettingsView() } label: { Label("管理账户与通知", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity) }.buttonStyle(CapsuleButtonStyle())
                SectionHeading(title: "关于", subtitle: "OVH · 1.2.0")
                VStack(alignment: .leading, spacing: 14) {
                    Text("SwiftUI 原生客户端，连接你部署的 gokele/ovh 后端。").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Link("开源面板 · gokele/ovh", destination: URL(string: "https://github.com/gokele/ovh")!).font(.system(size: 13))
                    Link("隐私政策", destination: URL(string: "https://ovh-review.hejingcheng.com/privacy")!).font(.system(size: 13)).accessibilityIdentifier("settings.privacy")
                    Link("技术支持与客户端源码", destination: URL(string: "https://ovh-review.hejingcheng.com/support")!).font(.system(size: 13))
                    Divider()
                    NavigationLink { LicenseView() } label: { HStack { Text("开源许可"); Spacer(); Image(systemName: "chevron.right").font(.system(size: 11)) }.font(.system(size: 13)) }.buttonStyle(.plain).accessibilityIdentifier("settings.license")
                }.padding(16).panel()
                Button("断开此设备的连接", role: .destructive) { signingOut = true }.buttonStyle(CapsuleButtonStyle()).accessibilityIdentifier("settings.disconnect")
            }.padding(14).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.accessibilityIdentifier("settings.scroll").page("连接与设备", back: true)
            .alert("断开此设备的连接？", isPresented: $signingOut) {
                Button("断开并移除本机凭据", role: .destructive) { store.disconnect() }
                Button("取消", role: .cancel) {}
            } message: { Text("本机登录凭据会移除。再次连接可扫码配对或输入面板访问密钥。设备授权可以在网页设置中单独撤销。") }
    }
}

struct LicenseView: View {
    var body: some View {
        ScrollView { Text((try? String(contentsOf: Bundle.main.url(forResource: "LICENSE", withExtension: "txt")!, encoding: .utf8)) ?? "AGPL-3.0").font(.system(size: 12, design: .monospaced)).padding(14) }
            .page("AGPL-3.0", back: true, showAccount: false)
    }
}

struct SectionHeading: View {
    let title: String
    let subtitle: String
    var body: some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 14, weight: .semibold)); Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.muted) } }
}

struct MetricCard: View {
    let title: String
    let value: String
    let symbol: String
    var footnote: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Text(title).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1); Spacer(minLength: 0); Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Theme.muted) }
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
            Text(footnote ?? " ").font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).panel()
    }
}

struct StatusBadge: View {
    let text: String
    let healthy: Bool
    var tone: Color { healthy ? Theme.success : Theme.warning }
    var body: some View {
        HStack(spacing: 5) { Circle().fill(tone).frame(width: 5, height: 5); Text(text).font(.system(size: 11, weight: .medium)) }
            .padding(.horizontal, 8).padding(.vertical, 4).foregroundStyle(tone).background(tone.opacity(0.08), in: Capsule())
            .overlay { Capsule().strokeBorder(tone.opacity(0.30), lineWidth: 1) }
    }
}

struct StatusRow: View {
    let title: String
    let value: String
    let active: Bool
    var body: some View { HStack { Text(title).font(.system(size: 12)).foregroundStyle(Theme.muted); Spacer(); StatusBadge(text: value, healthy: active) } }
}

struct ErrorCard: View {
    let message: String
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 9) { Label(message, systemImage: "exclamationmark.triangle").font(.system(size: 12)); if let retry { Button("重新加载", action: retry).font(.system(size: 12)).buttonStyle(.plain) } }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14).foregroundStyle(Theme.warning)
            .background(Theme.warning.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.warning.opacity(0.3), lineWidth: 1).allowsHitTesting(false) }
    }
}

struct PowerButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View { Button(action: action) { Label(title, systemImage: symbol).frame(maxWidth: .infinity) }.buttonStyle(CapsuleButtonStyle()) }
}
