import SwiftUI

/// Mirrors web/hooks/use-availability.ts: public stock is region scoped and sends no panel credentials.
@MainActor final class NativeMarket: ObservableObject {
    @Published var variants: [JSONValue] = []
    @Published var error: String?
    @Published var loading = false
    @Published var updated: Date?
    private var revision = 0
    private var accountID = ""
    typealias Fetch = (URLRequest, URL) async throws -> JSONValue
    private let fetch: Fetch
    init(fetch: @escaping Fetch = { request, origin in try await APIClient.send(request, origin: origin) }) { self.fetch = fetch }
    func load(store: AppStore, account snapshot: OVHAccount? = nil) async {
        guard !Task.isCancelled, let account = snapshot ?? store.activeAccount else { return }
        revision += 1; let ticket = revision, session = store.sessionID
        let scope = account.id + "|" + account.endpoint + "|" + session.uuidString
        if accountID != scope { variants = []; updated = nil; accountID = scope }
        loading = true; error = nil
        defer { if revision == ticket { loading = false } }
        let bases = ["EU":"https://eu.api.ovh.com","CA":"https://ca.api.ovh.com","US":"https://api.us.ovhcloud.com"]
        var url = (bases[account.region] ?? bases["EU"]!) + "/v1/dedicated/server/datacenter/availabilities"
        #if DEBUG && targetEnvironment(simulator)
        if store.connection?.address == "https://localhost:16443" { url = "https://localhost:16443/qa/availability?region=" + account.region }
        #endif
        var request = URLRequest(url: URL(string:url)!); request.timeoutInterval = 30
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        do {
            let value = try await fetch(request, URL(string:url)!)
            guard !Task.isCancelled, ticket == revision, session == store.sessionID, store.activeAccount == account else { return }
            variants = value.array; updated = Date()
        } catch {
            guard !Task.isCancelled, !APIClient.isCancellation(error), ticket == revision,
                  session == store.sessionID, store.activeAccount == account else { return }
            self.error = "实时库存：" + error.localizedDescription
        }
    }
    var index: [String:[String:String]] { Self.index(variants) }
    nonisolated static func index(_ variants:[JSONValue]) -> [String:[String:String]] {
        var result:[String:[String:String]] = [:]
        for item in variants {
            let plan = item["planCode"].rawText
            for dc in item["datacenters"].array {
                let code = dc["datacenter"].rawText.lowercased(), status = dc["availability"].rawText
                if !NativeStock.orderable(result[plan]?[code] ?? "") { result[plan,default:[:]][code] = status }
            }
        }
        return result
    }
    nonisolated static func optionAvailable(_ option:String,variants:[JSONValue],plan:String) -> Bool? {
        let rows=variants.filter { $0["planCode"].rawText == plan }
        guard !rows.isEmpty else { return nil }
        return rows.contains { item in
            let parts=item["fqn"].rawText.split(separator:".").dropFirst().map(String.init)
            return parts.contains { $0 == option || option.hasPrefix($0 + "-") || $0.hasPrefix(option + "-") } && item["datacenters"].array.contains { NativeStock.orderable($0["availability"].rawText) }
        }
    }
}

/// Owns the read requests rather than inheriting the short-lived refresh-control task.
/// Concurrent refresh triggers join one request; changing account or leaving cancels it.
@MainActor final class NativeInventoryRequests: ObservableObject {
    private var task: Task<Void, Never>?
    private var scope = ""
    private var forced = false
    private var revision = 0
    func load(store: AppStore, includeAPI: Bool, force: Bool = false, loader: NativeLoader, catalog: NativeLoader, market: NativeMarket) async {
        guard !Task.isCancelled || force, let account = store.activeAccount, store.connection != nil else { return }
        let identity = store.sessionID.uuidString + "|" + account.id + "|" + account.endpoint + "|" + account.zone + "|" + String(includeAPI)
        if let task, scope == identity, !force || forced { await task.value; return }
        cancel()
        scope = identity; forced = force
        let ticket = revision
        // Snapshot all three scopes before suspension, so a new account cannot supply
        // the price subsidiary or stock endpoint to an older catalog request.
        let pending = Task {
            async let plans: () = loader.load("/servers", store: store, account: account.id,
                query: ["showApiServers":String(includeAPI || force),"forceRefresh":String(force)], requireActiveAccount: true)
            async let prices: () = catalog.load("/catalog", store: store, account: account.id,
                query: ["subsidiary":account.zone,"forceRefresh":String(force)], requireActiveAccount: true)
            async let stock: () = market.load(store: store, account: account)
            _ = await (plans, prices, stock)
        }
        task = pending
        await pending.value
        if revision == ticket { task = nil }
    }
    func cancel() { revision += 1; task?.cancel(); task = nil }
}

struct NativePrice {
    var monthly: Double
    var tax: Double
    var installation: Double
    var installationTax: Double
    var currency: String
    var formatted: String { money(monthly) + " / 月" }
    func money(_ value:Double) -> String { currency.isEmpty ? value.formatted(.number.precision(.fractionLength(2))) + "（无币种）" : value.formatted(.currency(code:currency)) }
}

struct NativePriceIndex {
    let plans: [String:JSONValue]
    let addons: [String:JSONValue]
    let currency: String
    init(_ catalog:JSONValue) {
        plans = Dictionary(catalog["plans"].array.map { ($0["planCode"].rawText,$0) },uniquingKeysWith:{ _,new in new })
        addons = Dictionary(catalog["addons"].array.map { ($0["planCode"].rawText,$0) },uniquingKeysWith:{ _,new in new })
        currency = catalog["locale"]["currencyCode"].rawText
    }
    func price(plan:String,options:[String]) -> NativePrice? {
        guard let base=plans[plan], let month=Self.monthly(base) else { return nil }
        let install=Self.installation(base)
        var price=NativePrice(monthly:month.0,tax:month.1,installation:install.0,installationTax:install.1,currency:currency)
        for code in options where !code.isEmpty {
            guard let addon=addons[code] else { continue }
            if let month=Self.monthly(addon) { price.monthly += month.0; price.tax += month.1 }
            let installation=Self.installation(addon); price.installation += installation.0; price.installationTax += installation.1
        }
        return price
    }
    private static func monthly(_ plan:JSONValue) -> (Double,Double)? {
        guard let row=plan["pricings"].array.first(where:{ $0["intervalUnit"].rawText == "month" && $0["interval"].number == 1 && $0["mode"].rawText == "default" && !$0["capacities"].array.contains(.string("installation")) }), let amount=row["price"].number else { return nil }
        return (amount / 1e8,(row["tax"].number ?? 0) / 1e8)
    }
    private static func installation(_ plan:JSONValue) -> (Double,Double) {
        guard let row=plan["pricings"].array.first(where:{ $0["mode"].rawText == "default" && $0["capacities"].array.contains(.string("installation")) }) else { return (0,0) }
        return ((row["price"].number ?? 0) / 1e8,(row["tax"].number ?? 0) / 1e8)
    }
}
