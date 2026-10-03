import SwiftUI

extension AppStore {
    var nativeContext: NativeContext { .init(account: selectedAccountID, accountName: activeAccount?.name ?? "当前账户") }
}

struct NativeDestinationView: View {
    let destination: ConsoleDestination
    var body: some View {
        switch destination.path {
        case "/servers": NativeServersView(back: true)
        case "/queue": NativeQueueView(back: true)
        case "/monitor": NativeMonitorView(back: true)
        case "/vps-monitor": NativeMonitorView(vps: true, back: true)
        case "/server-control": AssetsView(back: true)
        case "/vps-control": AssetsView(kind: .vps, back: true)
        case "/history": NativeRecordsView(kind: .history)
        case "/logs": NativeRecordsView(kind: .logs)
        case "/account": NativeAccountView()
        case "/settings": NativeSettingsView()
        case "/connection": SettingsView()
        default: NativeMoreView()
        }
    }
}

struct NativeEmptyView: View {
    let title: String
    var subtitle = ""
    var symbol = "tray"
    var body: some View { VStack(spacing: 12) { Image(systemName: symbol).font(.system(size: 32, weight: .light)).foregroundStyle(Theme.muted); Text(title).font(.system(size: 16, weight: .semibold)); if !subtitle.isEmpty { Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center) } }.frame(maxWidth: .infinity).padding(.vertical, 38).panel() }
}

struct NativeLoadingState: View {
    @ObservedObject var loader: NativeLoader
    var showNotices = true
    var body: some View {
        if loader.loading { ProgressView("同步中…").frame(maxWidth: .infinity) }
        if let error = loader.error { ErrorCard(message: error) }
        if showNotices { ForEach(loader.notices, id: \.self) { ErrorCard(message: $0) } }
    }
}

struct NativeServersView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var loader = NativeLoader()
    @StateObject private var catalog = NativeLoader()
    @StateObject private var market = NativeMarket()
    @StateObject private var requests = NativeInventoryRequests()
    @State private var search = ""
    @State private var onlyAvailable = false
    @State private var includeAPI = false
    @State private var family = "全部"
    var back = false
    private var loadIdentity: String { store.sessionID.uuidString + "|" + store.selectedAccountID + "|" + String(includeAPI) + "|" + String(store.nativeRevision) }
    private var expiredNotice: String? {
        guard loader.value["cacheInfo"]["usingExpiredCache"].bool == true else { return nil }
        if let notice = loader.notices.first(where: { $0.hasPrefix("当前展示旧目录缓存") }) { return notice }
        let minutes = loader.value["cacheInfo"]["cacheAgeMinutes"].number.map { String(Int($0)) }
        return APIClient.cacheWarning("Using expired cache" + (minutes.map { " (\($0) minutes old)" } ?? ""))
    }
    private var plans: [JSONValue] { loader.value["servers"].array.isEmpty ? loader.value.array : loader.value["servers"].array }
    private var displayedPlans: [JSONValue] {
        let liveIndex = market.index
        return plans.map { plan in
        guard let live = liveIndex[plan["planCode"].rawText] else { return plan }
        var object = plan.object
        object["datacenters"] = .array(live.keys.sorted().map { dc in .object(["datacenter":.string(dc),"availability":.string(live[dc] ?? "unknown")]) })
        return .object(object)
    } }
    private var prices: [String:NativePrice] {
        let index = NativePriceIndex(catalog.value)
        return Dictionary(plans.compactMap { plan -> (String,NativePrice)? in
            let code=plan["planCode"].rawText
            guard let price=index.price(plan:code,options:plan["defaultOptions"].array.map { $0["value"].rawText }) else { return nil }
            return (code,price)
        },uniquingKeysWith:{ _,new in new })
    }
    private var filtered: [JSONValue] { displayedPlans.filter { plan in
        let content = ["name","planCode","cpu","memory","storage","description"].map { plan[$0].rawText }.joined(separator: " ")
        return (search.isEmpty || content.localizedCaseInsensitiveContains(search)) && (!onlyAvailable || plan["datacenters"].array.contains(where: { NativeStock.orderable($0["availability"].rawText) })) && (family == "全部" || content.uppercased().contains(family))
    } }
    var body: some View {
        let prices = self.prices
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("机型、价格、库存按当前账户所在站点显示").font(.system(size: 12)).foregroundStyle(Theme.muted)
                TextField("搜索机型、CPU、内存或硬盘", text: $search).inputStyle().accessibilityIdentifier("servers.search")
                ScrollView(.horizontal) { HStack { ForEach(["全部","KS","SYS","RISE","ADV","GAME"], id: \.self) { tag in Button(tag) { family = tag }.buttonStyle(CapsuleButtonStyle(solid: family == tag)) } } }
                HStack { Toggle("仅显示有货", isOn: $onlyAvailable); Toggle("含 API 机型", isOn: $includeAPI).accessibilityIdentifier("servers.includeAPI") }.font(.system(size: 12)).tint(Theme.primary)
                NativeLoadingState(loader: loader, showNotices: false)
                ForEach(loader.notices.filter { !($0.hasPrefix("当前展示旧目录缓存") && expiredNotice != nil) }, id: \.self) { ErrorCard(message:$0) }
                if let error = catalog.error { ErrorCard(message: "价格目录：" + error) }
                if let error = market.error { ErrorCard(message: error + (market.updated == nil ? "。暂时保留目录库存" : "。暂时保留上次查询的库存") + "，请刷新或进入详情再次查询。") }
                if let date = market.updated { Text("上次库存查询 " + date.formatted(date:.omitted,time:.shortened)).font(.system(size:11)).foregroundStyle(Theme.muted).accessibilityIdentifier("servers.stockUpdated") }
                if let timestamp = loader.value["cacheInfo"]["timestamp"].number {
                    HStack {
                        Text("目录更新于 " + Date(timeIntervalSince1970: timestamp).formatted(date: .omitted, time: .shortened))
                        Spacer()
                        Button("重新拉取") { Task { await load(force: true) } }.disabled(loader.loading || catalog.loading || market.loading).accessibilityIdentifier("servers.refresh")
                    }.font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                if let notice = expiredNotice { ErrorCard(message:notice).accessibilityIdentifier("servers.expiredCache") }
                Text("\(filtered.count) 个机型").font(.system(size: 12)).foregroundStyle(Theme.muted)
                if filtered.isEmpty && !loader.loading { NativeEmptyView(title: plans.isEmpty ? "暂无机型" : "没有匹配的机型", subtitle: "可以刷新目录，或调整筛选条件。", symbol: "server.rack") }
                ForEach(Array(filtered.enumerated()), id: \.offset) { row in
                    NavigationLink { NativePlanView(plan: row.element, context: store.nativeContext, catalog: catalog.value, variants: market.variants) } label: { NativePlanCard(plan: row.element, price: prices[row.element["planCode"].rawText]) }.buttonStyle(.plain).accessibilityIdentifier("plan." + row.element["planCode"].rawText)
                }
            }.padding(14).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.page("服务器列表", back: back).task(id: loadIdentity) { await load() }
            .onDisappear { requests.cancel() }
            .nativeRefreshable { await load(force: true) }
    }
    private func load(force: Bool = false) async {
        await requests.load(store:store, includeAPI:includeAPI, force:force, loader:loader, catalog:catalog, market:market)
    }
}

enum NativeStock {
    static func orderable(_ status: String) -> Bool { status.range(of: #"^\d+H(-high|-low)?$"#, options: .regularExpression) != nil }
    static func label(_ status: String) -> String { if orderable(status) { return "有货 · " + status }; return ["unavailable":"无货","comingSoon":"即将上架","unknown":"未知","":"未查询"][status] ?? status }
}

struct NativePlanCard: View {
    let plan: JSONValue
    var price: NativePrice?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { VStack(alignment: .leading, spacing: 4) { Text(plan["name"].text ?? plan["planCode"].rawText).font(.system(size: 17, weight: .semibold)); Text(plan["planCode"].rawText).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(Theme.muted) }
            if let description = plan["description"].text, !description.isEmpty { Text(description).font(.system(size: 12)).foregroundStyle(Theme.muted) }
            Text(price?.formatted ?? "— · 当前站点暂无报价").font(.system(size:16,weight:.semibold))
            ForEach([("cpu","cpu"),("memory","memorychip"),("storage","internaldrive"),("bandwidth","network")], id: \.0) { key, symbol in
                if let text = plan[key].text, !text.isEmpty { Label(text, systemImage: symbol).font(.system(size: 12)).foregroundStyle(Theme.muted) }
            }
            FlowTags(items: plan["datacenters"].array.map { ($0["datacenter"].rawText.uppercased(), NativeStock.orderable($0["availability"].rawText)) })
        }.padding(16).panel()
    }
}

struct FlowTags: View {
    let items: [(String, Bool)]
    var body: some View { LazyVGrid(columns: [GridItem(.adaptive(minimum: 75), alignment: .leading)], alignment: .leading, spacing: 6) { ForEach(Array(items.enumerated()), id: \.offset) { item in StatusBadge(text: item.element.0, healthy: item.element.1) } } }
}

struct NativePlanView: View {
    @EnvironmentObject var store: AppStore
    let plan: JSONValue
    let context: NativeContext
    var catalog: JSONValue = .null
    var variants: [JSONValue] = []
    @StateObject private var stock = NativeLoader()
    @State private var options: [String] = []
    @State private var pricing: JSONValue = .null
    @State private var priceBusy = false
    @State private var error: String?
    @State private var datacenter = ""
    private var code: String { plan["planCode"].rawText }
    private var availableOptions: [JSONValue] { plan["availableOptions"].array }
    private var groups: [String] { Array(Set(availableOptions.map { $0["family"].text ?? "其他" })).sorted() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NativePlanCard(plan: plan, price: NativePriceIndex(catalog).price(plan:code,options:options))
                Text(context.accountName).font(.system(size: 12)).foregroundStyle(Theme.muted)
                ForEach(groups, id: \.self) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(NativeCatalog.label(group)).font(.system(size: 14, weight: .semibold))
                        ForEach(Array(availableOptions.filter { ($0["family"].text ?? "其他") == group }.enumerated()), id: \.offset) { item in
                            let value = item.element["value"].rawText
                            Button { options.removeAll { current in availableOptions.contains { ($0["family"].text ?? "其他") == group && $0["value"].rawText == current } }; options.append(value); pricing = .null } label: {
                                HStack { if let available=NativeMarket.optionAvailable(value,variants:variants,plan:code) { Circle().fill(available ? Theme.success : Theme.muted.opacity(0.4)).frame(width:6,height:6) }; Text(item.element["label"].text ?? value).font(.system(size: 13)); Spacer(); Image(systemName: options.contains(value) ? "checkmark.circle.fill" : "circle").foregroundStyle(options.contains(value) ? Theme.primary : Theme.muted) }.padding(10).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.padding(14).panel()
                }
                NativeLoadingState(loader: stock)
                VStack(alignment: .leading, spacing: 12) {
                    Label("实时库存", systemImage: "shippingbox").font(.system(size: 14, weight: .semibold))
                    ForEach(stock.value.object.keys.sorted(), id: \.self) { dc in
                        HStack { Text(dc.uppercased()); Spacer(); StatusBadge(text: NativeStock.label(stock.value[dc].rawText), healthy: NativeStock.orderable(stock.value[dc].rawText)) }.font(.system(size: 13))
                    }
                    Button("刷新所选配置库存") { Task { await loadStock() } }.buttonStyle(CapsuleButtonStyle())
                }.padding(16).panel()
                VStack(alignment: .leading, spacing: 12) {
                    Text("配置价格").font(.system(size: 14, weight: .semibold))
                    if let price=NativePriceIndex(catalog).price(plan:code,options:options) {
                        Text(price.formatted).font(.system(size:20,weight:.semibold))
                        Text("含税月费 " + price.money(price.monthly + price.tax) + " · 安装费 " + price.money(price.installation + price.installationTax)).font(.system(size:12)).foregroundStyle(Theme.muted)
                        Text("目录参考价，最终价格以 OVH 购物车报价为准。").font(.system(size:11)).foregroundStyle(Theme.muted)
                    }
                    Picker("报价机房", selection: $datacenter) { ForEach(plan["datacenters"].array.compactMap { $0["datacenter"].text }, id: \.self) { Text($0.uppercased()).tag($0) } }
                    if let error { ErrorCard(message: error) }
                    Button { Task { await quote() } } label: { Label(priceBusy ? "查询中…" : "查询当前配置价格", systemImage: "tag") }.buttonStyle(CapsuleButtonStyle()).disabled(priceBusy)
                    if pricing != .null { NativeDataView(value: pricing) }
                }.padding(16).panel()
                NavigationLink { NativeOrderView(plan: plan, context: context, options: options) } label: { Label("创建抢购任务", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(CapsuleButtonStyle(solid: true)).accessibilityIdentifier("plan.order")
                NativeOperationLink(operation: NativeCatalog.shared.operation("POST", "/queue/quick-order"), context: .init(account: context.account, accountName: context.accountName, bindings: ["planCode":.string(code)]), seed: ["account_id":.string(context.account),"datacenter":.string(datacenter),"options":.array(options.map(JSONValue.string)),"autoPay":.bool(false)]).panel()
                NativeOperationLink(operation: NativeCatalog.shared.operation("POST", "/monitor/subscriptions"), context: context, seed: ["planCode":.string(code),"options":.array(options.map(JSONValue.string)),"notifyAvailable":.bool(true),"notifyUnavailable":.bool(false),"autoOrder":.bool(false),"autoPay":.bool(false),"quantity":.number(1),"autoOrderAccountId":.string(context.account)]).panel()
            }.padding(14).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.page(plan["name"].text ?? code, back: true, showAccount: false)
            .task { options = plan["defaultOptions"].array.compactMap { $0["value"].text }; datacenter = plan["datacenters"].array.first?["datacenter"].text ?? ""; await loadStock() }
            .onChange(of: options) { _, _ in Task { await loadStock() } }
    }
    private func loadStock() async { await stock.load("/availability/" + APIClient.component(code), store: store, account: context.account, query: ["options":options.joined(separator: ",")]) }
    private func quote() async {
        guard let connection = store.connection, !priceBusy else { return }; priceBusy = true; error = nil
        defer { priceBusy = false }
        do { let r = try await APIClient(connection: connection).value("/servers/" + APIClient.component(code) + "/price", account: context.account, method: "POST", body: .object(["account_id":.string(context.account),"datacenter":.string(datacenter),"options":.array(options.map(JSONValue.string))])); pricing = r.value }
        catch { self.error = error.localizedDescription }
    }
}

struct NativeOrderView: View {
    @EnvironmentObject var store: AppStore
    let plan: JSONValue
    let context: NativeContext
    let options: [String]
    @State private var datacenters: Set<String> = []
    @State private var quantity = 1
    @State private var interval = 60
    @State private var autoPay = false
    @State private var confirming = false
    @State private var submitting = false
    @State private var submitted = 0
    @State private var error: String?
    @State private var completed = false
    var total: Int { datacenters.count * quantity }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NativePlanCard(plan: plan)
                Text("下单账户：" + context.accountName).font(.system(size: 13, weight: .medium))
                VStack(alignment: .leading, spacing: 12) {
                    Text("数据中心").font(.system(size: 14, weight: .semibold))
                    ForEach(plan["datacenters"].array.compactMap { $0["datacenter"].text }, id: \.self) { dc in
                        Toggle(dc.uppercased(), isOn: Binding(get: { datacenters.contains(dc) }, set: { if $0 { datacenters.insert(dc) } else { datacenters.remove(dc) } })).font(.system(size: 13)).tint(Theme.primary)
                    }
                    Stepper("每个机房 \(quantity) 台", value: $quantity, in: 1...20).font(.system(size: 13))
                    HStack { Text("重试间隔（秒）"); Spacer(); TextField("60", value: $interval, format: .number).keyboardType(.numberPad).frame(width: 90).multilineTextAlignment(.trailing) }.font(.system(size: 13))
                    Toggle("下单成功后自动付款", isOn: $autoPay).font(.system(size: 13)).tint(Theme.primary)
                    if autoPay { ErrorCard(message: "成功下单后会使用该 OVH 账户的默认支付方式扣款。") }
                    Text("共创建 \(total) 个任务；每次最多 60 个任务。").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }.padding(16).panel().disabled(submitting || submitted > 0)
                if let error { ErrorCard(message: error) }
                if submitting || submitted > 0 { ProgressView("已创建 \(submitted) / \(total)", value: Double(submitted), total: Double(max(total,1))) }
                if completed { Label("任务已创建，后端会持续尝试下单。", systemImage: "checkmark.circle").font(.system(size: 13)).foregroundStyle(Theme.success) }
                Button { confirming = true } label: { Text(submitting ? "创建中…" : "创建 \(total) 个抢购任务").frame(maxWidth: .infinity) }.buttonStyle(CapsuleButtonStyle(solid: true)).disabled(submitting || completed || submitted > 0 || total == 0 || total > 60 || !(1...86400).contains(interval)).accessibilityIdentifier("order.submit")
                if submitted > 0 && !completed { NavigationLink { NativeQueueView(back: true) } label: { Text("核对已创建的队列任务") }.buttonStyle(CapsuleButtonStyle()) }
            }.padding(14)
        }.page("创建抢购任务", back: true, showAccount: false)
            .disabled(submitting)
            .sheet(isPresented: $confirming) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(orderSummary).font(.system(size: 15)).lineSpacing(8)
                        if autoPay { ErrorCard(message: "下单成功后会使用该账户的默认支付方式付款。") }
                        Button("确认创建") { confirming = false; Task { await submit() } }.buttonStyle(CapsuleButtonStyle(solid: true))
                        Spacer()
                    }.padding(20).navigationTitle("确认创建抢购任务").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { confirming = false } } }
                }.presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
            }
    }
    private var orderSummary: String {
        let places = datacenters.sorted().joined(separator: "、")
        let payment = autoPay ? "已启用自动付款" : "下单后手动付款"
        return [context.accountName, plan["planCode"].rawText, places + " · \(total) 个任务", payment].joined(separator: "\n")
    }
    private func submit() async {
        guard !submitting, let connection = store.connection, total > 0, total <= 60 else { return }
        submitting = true; error = nil; defer { submitting = false }
        let requests = datacenters.sorted().flatMap { dc in (0..<quantity).map { _ in dc } }
        do {
            for dc in requests.dropFirst(submitted) {
                _ = try await APIClient(connection: connection).value("/queue", method: "POST", body: .object(["account_id":.string(context.account),"planCode":plan["planCode"],"datacenter":.string(dc),"options":.array(options.map(JSONValue.string)),"retryInterval":.number(Double(interval)),"autoPay":.bool(autoPay)]))
                submitted += 1
            }
            completed = true; await store.refresh(includeAccounts: false)
        } catch { self.error = "已确认创建 \(submitted) 个任务。" + error.localizedDescription + "\n请先核对队列；网络错误时最后一个请求可能已创建成功，避免重复下单。" }
    }
}

struct NativeQueueView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var loader = NativeLoader()
    @State private var status = "全部"
    @State private var search = ""
    @State private var allAccounts = false
    @State private var selectionMode = false
    @State private var selected: Set<String> = []
    var back = false
    private var items: [JSONValue] { loader.value.array.filter { item in (allAccounts || item["accountId"].rawText == store.selectedAccountID) && (status == "全部" || item["status"].rawText == status) && (search.isEmpty || (item["planCode"].rawText + item["datacenter"].rawText).localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                HStack { NavigationLink { NativeServersView(back: true) } label: { Label("创建任务", systemImage: "plus") }.buttonStyle(CapsuleButtonStyle(solid: true)); Spacer(); Toggle("全部账户", isOn: $allAccounts).font(.system(size: 12)).tint(Theme.primary).fixedSize() }
                HStack { Button(selectionMode ? "完成选择" : "批量选择") { selectionMode.toggle(); if !selectionMode { selected = [] } }.buttonStyle(CapsuleButtonStyle()); if selectionMode { Button(selected.count == items.count ? "取消全选" : "全选") { selected = selected.count == items.count ? [] : Set(items.map { $0["id"].rawText }) }.buttonStyle(CapsuleButtonStyle()) } }
                if !selected.isEmpty { NativeQueueBatchBar(items: items.filter { selected.contains($0["id"].rawText) }, onComplete: { selected = []; Task { await load() } }) }
                TextField("搜索机型或机房", text: $search).inputStyle()
                Picker("任务状态", selection: $status) { Text("全部").tag("全部"); Text("运行中").tag("running"); Text("暂停").tag("paused"); Text("成功").tag("success"); Text("失败").tag("failed") }.pickerStyle(.segmented)
                NativeLoadingState(loader: loader)
                if items.isEmpty && !loader.loading { NativeEmptyView(title: "暂无抢购任务", subtitle: "从服务器列表选择机型与配置后创建。", symbol: "calendar") }
                ForEach(Array(items.enumerated()), id: \.offset) { item in
                    HStack(spacing: 10) {
                    if selectionMode { Button { let id = item.element["id"].rawText; if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } } label: { Image(systemName: selected.contains(item.element["id"].rawText) ? "checkmark.circle.fill" : "circle").font(.system(size: 21)) }.buttonStyle(.plain).accessibilityLabel("选择任务") }
                    NavigationLink { NativeQueueDetailView(item: item.element) } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text(item.element["planCode"].rawText).font(.system(size: 15, weight: .semibold)); Spacer(); StatusBadge(text: queueLabel(item.element["status"].rawText), healthy: item.element["status"].rawText == "running") }
                            HStack { Text(item.element["datacenter"].rawText.uppercased()); Spacer(); Text("尝试 \(item.element["retryCount"].text ?? "0") 次") }.font(.system(size: 12)).foregroundStyle(Theme.muted)
                            Text(store.accounts.first { $0.id == item.element["accountId"].rawText }?.name ?? "账户不可用").font(.system(size: 11)).foregroundStyle(Theme.muted)
                        }.padding(16).panel()
                    }.buttonStyle(.plain)
                    }
                }
                NativeOperationLink(operation: NativeCatalog.shared.operation("DELETE", "/queue/clear"), context: store.nativeContext).panel()
                NativeOperationLink(operation: NativeCatalog.shared.operation("/queue/timings"), context: store.nativeContext).panel()
            }.padding(14).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.page("抢购队列", back: back).task(id: store.selectedAccountID) { await load() }.nativeRefreshable { await load() }
            .onChange(of: store.nativeRevision) { _,_ in Task { await load() } }
            .onChange(of: store.selectedAccountID) { _,_ in selected = [] }
            .task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(10)); if Task.isCancelled { break }; await load() } }
    }
    private func load() async { await loader.load("/queue", store: store) }
    private func queueLabel(_ v: String) -> String { ["running":"运行中","pending":"等待中","paused":"已暂停","success":"下单成功","completed":"已完成","failed":"失败"][v] ?? v }
}

struct NativeQueueDetailView: View {
    @EnvironmentObject var store: AppStore
    let item: JSONValue
    private var context: NativeContext { .init(account: item["accountId"].rawText, accountName: store.accounts.first { $0.id == item["accountId"].rawText }?.name ?? "当前任务账户", bindings: ["id":item["id"]]) }
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                NativeDataView(value: item).padding(16).panel()
                NativeOperationLink(operation: NativeCatalog.shared.operation("PUT", "/queue/:id/status"), context: context, seed: ["status":item["status"]]).panel()
                NativeOperationLink(operation: NativeCatalog.shared.operation("PUT", "/queue/:id/interval"), context: context, seed: ["retryInterval":item["retryInterval"]]).panel()
                NativeOperationLink(operation: NativeCatalog.shared.operation("DELETE", "/queue/:id"), context: context).panel()
            }.padding(14)
        }.page("抢购任务", back: true, showAccount: false)
    }
}

struct NativeMonitorView: View {
    @EnvironmentObject var store: AppStore
    var vps = false
    var back = false
    @StateObject private var loader = NativeLoader()
    @StateObject private var status = NativeLoader()
    @State private var search = ""
    private var root: String { vps ? "/vps-monitor" : "/monitor" }
    private var items: [JSONValue] { loader.value.array.filter { search.isEmpty || $0["planCode"].rawText.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if !vps { NavigationLink { NativeMonitorView(vps: true, back: true) } label: { HStack { Label("VPS 补货监控", systemImage: "cloud"); Spacer(); Image(systemName: "chevron.right") } }.buttonStyle(CapsuleButtonStyle()) }
                HStack(spacing: 10) {
                    MetricCard(title: "订阅数量", value: String(loader.value.array.count), symbol: "bell")
                    MetricCard(title: "检查间隔", value: (status.value["check_interval"].text ?? "—") + "s", symbol: "timer")
                }
                VStack(spacing: 0) {
                    StatusRow(title: "监控引擎", value: status.value["running"].bool == true ? "运行中" : "未运行", active: status.value["running"].bool == true).padding(14)
                    Divider()
                    NativeOperationLink(operation: NativeCatalog.shared.operation("POST", root + (status.value["running"].bool == true ? "/stop" : "/start")), context: store.nativeContext).disabled(status.loading || status.value["running"].bool == nil || status.error != nil)
                    Divider(); NativeOperationLink(operation: NativeCatalog.shared.operation("PUT", root + "/interval"), context: store.nativeContext, seed: ["interval":status.value["check_interval"]])
                }.panel()
                NativeLoadingState(loader: loader)
                if let error = status.error { ErrorCard(message: "监控状态：" + error) }
                HStack {
                    if vps { NavigationLink { NativeVPSModelsView() } label: { Label("添加订阅", systemImage: "plus") }.buttonStyle(CapsuleButtonStyle(solid: true)) }
                    else { NavigationLink { NativeServersView(back: true) } label: { Label("添加订阅", systemImage: "plus") }.buttonStyle(CapsuleButtonStyle(solid: true)) }
                    Spacer(); Text("\(items.count) 个订阅").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                TextField("搜索机型", text: $search).inputStyle()
                if items.isEmpty && !loader.loading { NativeEmptyView(title: "暂无监控订阅", subtitle: "选择机型和配置，设置通知与自动抢购。", symbol: "bell") }
                ForEach(Array(items.enumerated()), id: \.offset) { item in NavigationLink { NativeSubscriptionView(item: item.element, vps: vps) } label: { subscriptionCard(item.element) }.buttonStyle(.plain) }
                if !vps { NativeOperationLink(operation: NativeCatalog.shared.operation("POST", "/monitor/subscriptions/batch-add-all"), context: store.nativeContext).panel() }
                NativeOperationLink(operation: NativeCatalog.shared.operation("DELETE", root + "/subscriptions/clear"), context: store.nativeContext).panel()
            }.padding(14).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.page(vps ? "VPS 补货" : "服务器监控", back: back).task(id: store.selectedAccountID) { await load() }.nativeRefreshable { await load() }
            .onChange(of: store.nativeRevision) { _,_ in Task { await load() } }
            .task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(30)); if Task.isCancelled { break }; await load() } }
    }
    private func subscriptionCard(_ item: JSONValue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(item["serverName"].text ?? item["planCode"].rawText).font(.system(size: 15, weight: .semibold)); Spacer(); Image(systemName: "chevron.right").foregroundStyle(Theme.muted) }
            Text(item["planCode"].rawText).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
            FlowTags(items: item["lastStatus"].object.keys.sorted().map { ($0.uppercased(), NativeStock.orderable(item["lastStatus"][$0].rawText)) })
            HStack { Label(item["autoOrder"].bool == true ? "自动抢购" : "仅通知", systemImage: item["autoOrder"].bool == true ? "bolt" : "bell"); Spacer(); Text(item["datacenters"].array.isEmpty ? "全部机房" : item["datacenters"].array.map(\.rawText).joined(separator: "、").uppercased()) }.font(.system(size: 11)).foregroundStyle(Theme.muted)
            if item["retired"].bool == true { ErrorCard(message: "该套餐已下架，请调整订阅。") }
        }.padding(16).panel()
    }
    private func load() async { async let a: () = loader.load(root + "/subscriptions", store: store); async let b: () = status.load(root + "/status", store: store); _ = await (a,b) }
}

struct NativeSubscriptionView: View {
    @EnvironmentObject var store: AppStore
    let item: JSONValue
    let vps: Bool
    private var path: String { vps ? "/vps-monitor/subscriptions/:subscription_id" : "/monitor/subscriptions/:planCode" }
    private var context: NativeContext { .init(account: store.selectedAccountID, accountName: store.activeAccount?.name ?? "监控", bindings: vps ? ["subscription_id":item["id"]] : ["planCode":item["planCode"]]) }
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                NativeDataView(value: item).padding(16).panel()
                NativeOperationLink(operation: NativeCatalog.shared.operation("PUT", path), context: context, seed: item.object).panel()
                NativeOperationLink(operation: NativeCatalog.shared.operation(path + "/history"), context: context).panel()
                NativeOperationLink(operation: NativeCatalog.shared.operation("DELETE", path), context: context).panel()
            }.padding(14)
        }.page("监控订阅", back: true, showAccount: false)
    }
}

struct NativeVPSModelsView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var loader = NativeLoader()
    @State private var search = ""
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                TextField("搜索 VPS 机型", text: $search).inputStyle()
                NativeLoadingState(loader: loader)
                ForEach(Array(loader.value["models"].array.filter { search.isEmpty || ($0["planCode"].rawText + $0["name"].rawText).localizedCaseInsensitiveContains(search) }.enumerated()), id: \.offset) { item in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(item.element["name"].text ?? item.element["planCode"].rawText).font(.system(size: 16, weight: .semibold))
                        NativeDataView(value: item.element)
                        NativeOperationLink(operation: NativeCatalog.shared.operation("POST", "/vps-monitor/subscriptions"), context: store.nativeContext, seed: ["planCode":item.element["planCode"],"ovhSubsidiary":.string(store.activeAccount?.zone ?? "IE"),"monitorLinux":.bool(true),"monitorWindows":.bool(false),"notifyAvailable":.bool(true),"notifyUnavailable":.bool(false),"autoOrder":.bool(false),"autoPay":.bool(false),"autoOrderAccountId":.string(store.selectedAccountID),"quantity":.number(1)])
                        NativeOperationLink(operation: NativeCatalog.shared.operation("POST", "/vps-monitor/check/:plan_code"), context: .init(account: store.selectedAccountID, accountName: store.activeAccount?.name ?? "", bindings: ["plan_code":item.element["planCode"]]), seed: ["ovhSubsidiary":.string(store.activeAccount?.zone ?? "IE"),"accountId":.string(store.selectedAccountID)])
                    }.padding(14).panel()
                }
            }.padding(14)
        }.page("VPS 机型", back: true).task(id: store.selectedAccountID) { await loader.load("/vps-monitor/models", store: store, account: store.selectedAccountID, query: ["subsidiary":store.activeAccount?.zone ?? "IE"]) }.nativeRefreshable { await loader.load("/vps-monitor/models", store: store, account: store.selectedAccountID, query: ["subsidiary":store.activeAccount?.zone ?? "IE"]) }
    }
}
