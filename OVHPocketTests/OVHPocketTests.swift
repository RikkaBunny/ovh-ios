import XCTest
import CoreImage
import UIKit
@testable import OVHPocket

final class OVHPocketTests: XCTestCase {
    @MainActor private final class OverviewProbe {
        var delay: Double = 0
        var mode = "ok"
        var marker = 2
        var calls: [String: Int] = [:]
        func fetch(_ connection: Connection, path: String, account: String?) async throws -> JSONValue {
            calls[path, default:0] += 1
            let marker = self.marker, mode = self.mode, delay = self.delay
            // Deliberately noncooperative, so the store must reject late responses.
            if delay > 0 { try? await Task.sleep(for:.seconds(delay)) }
            if mode == "error" { throw PanelError.message("real refresh failure") }
            if mode == "cancel" { throw URLError(.cancelled) }
            let body: String
            switch path {
            case "/accounts": body = "{\"accounts\":[{\"id\":\"demo-eu\",\"name\":\"EU\",\"endpoint\":\"ovh-eu\",\"zone\":\"FR\",\"isDefault\":true},{\"id\":\"demo-us\",\"name\":\"US\",\"endpoint\":\"ovh-us\",\"zone\":\"US\",\"isDefault\":false}]}"
            case "/stats": body = "{\"activeQueues\":0,\"totalServers\":\(marker),\"availableServers\":1,\"purchaseSuccess\":0,\"purchaseFailed\":0}"
            case "/queue": body = "[]"
            case "/server-control/list": body = "{\"servers\":[]}"
            case "/vps-control/list": body = "{\"vps\":[{\"serviceName\":\"\(account ?? "global")-\(marker)\",\"displayName\":\"\(account ?? "global")\",\"state\":\"running\"}]}"
            default: body = "{}"
            }
            return try JSONDecoder().decode(JSONValue.self, from:Data(body.utf8))
        }
    }

    @MainActor func testOverviewRefreshSurvivesCallerCancellationAndCoalesces() async throws {
        let probe = OverviewProbe(), store = AppStore(fetch: { try await probe.fetch($0,path:$1,account:$2) })
        await store.connect(address:"https://localhost:16443",key:"OVH-AppReview-2026")
        defer { store.disconnect() }
        let previous = store.refreshedAt
        probe.calls = [:]; probe.delay = 0.3; probe.marker = 77
        let caller = Task { await store.refresh(includeAccounts:false) }
        try await Task.sleep(for:.milliseconds(30))
        let repeated = Task { await store.refresh(includeAccounts:false) }
        caller.cancel()
        await repeated.value; await caller.value
        XCTAssertEqual(probe.calls["/stats"],1)
        XCTAssertEqual(probe.calls["/vps-control/list"],1)
        XCTAssertEqual(store.stats?.totalServers,77)
        XCTAssertTrue(store.assets.first?.serviceName.hasSuffix("-77") == true)
        XCTAssertNotEqual(store.refreshedAt,previous)
        XCTAssertNil(store.error); XCTAssertFalse(store.loading)
    }

    @MainActor func testOverviewFailedRefreshRetainsDataAndOnlyReportsRealErrors() async throws {
        let probe = OverviewProbe(), store = AppStore(fetch: { try await probe.fetch($0,path:$1,account:$2) })
        await store.connect(address:"https://localhost:16443",key:"OVH-AppReview-2026")
        defer { store.disconnect() }
        let assets = store.assets, previous = store.refreshedAt
        probe.mode = "error"
        await store.refresh(includeAccounts:false)
        XCTAssertEqual(store.assets,assets); XCTAssertEqual(store.stats?.totalServers,2)
        XCTAssertEqual(store.refreshedAt,previous)
        XCTAssertTrue(store.error?.contains("real refresh failure") == true)
        probe.mode = "cancel"
        await store.refresh(includeAccounts:false)
        XCTAssertEqual(store.assets,assets); XCTAssertEqual(store.refreshedAt,previous)
        XCTAssertNil(store.error); XCTAssertFalse(store.loading)
        probe.mode = "ok"; probe.marker = 78
        await store.refresh(includeAccounts:false)
        XCTAssertEqual(store.stats?.totalServers,78); XCTAssertNil(store.error)
    }

    @MainActor func testOverviewOldScopeCannotOverwriteAccountOrDisconnectedSession() async throws {
        let probe = OverviewProbe(), store = AppStore(fetch: { try await probe.fetch($0,path:$1,account:$2) })
        await store.connect(address:"https://localhost:16443",key:"OVH-AppReview-2026")
        defer { store.disconnect() }
        store.selectAccount("demo-eu"); await store.refresh(includeAccounts:false)
        probe.delay = 0.4; probe.marker = 80
        let old = Task { await store.refresh(includeAccounts:false) }
        try await Task.sleep(for:.milliseconds(30))
        probe.marker = 81; store.selectAccount("demo-us")
        await store.refresh(includeAccounts:false); await old.value
        XCTAssertEqual(store.selectedAccountID,"demo-us")
        XCTAssertEqual(store.assets.map(\.serviceName),["demo-us-81"])
        XCTAssertEqual(store.stats?.totalServers,81)
        let pending = Task { await store.refresh(includeAccounts:false) }
        try await Task.sleep(for:.milliseconds(30)); store.disconnect()
        await pending.value
        XCTAssertNil(store.connection); XCTAssertTrue(store.assets.isEmpty)
        XCTAssertNil(store.stats); XCTAssertNil(store.refreshedAt); XCTAssertFalse(store.loading)
    }

    @MainActor func testPageRefreshOwnsReadAndCancelsOnScopeDeparture() async throws {
        let requests = NativeRefreshRequests()
        var starts = 0, completions = 0
        let operation: @MainActor () async -> Void = {
            starts += 1
            do { try await Task.sleep(for:.milliseconds(150)); completions += 1 } catch {}
        }
        let first = Task { await requests.run(scope:"EU",operation:operation) }
        try await Task.sleep(for:.milliseconds(20)); first.cancel()
        await requests.run(scope:"EU",operation:operation); await first.value
        XCTAssertEqual(starts,1); XCTAssertEqual(completions,1)
        let leaving = Task { await requests.run(scope:"EU",operation:operation) }
        try await Task.sleep(for:.milliseconds(20))
        await requests.run(scope:"US",operation:operation); await leaving.value
        XCTAssertEqual(starts,3); XCTAssertEqual(completions,2)
        let last = Task { await requests.run(scope:"US",operation:operation) }
        try await Task.sleep(for:.milliseconds(20)); requests.cancel(); await last.value
        XCTAssertEqual(completions,2)
    }

    func testCancellationClassificationDoesNotHideRealServerErrors() {
        XCTAssertTrue(APIClient.isCancellation(CancellationError()))
        XCTAssertTrue(APIClient.isCancellation(URLError(.cancelled)))
        XCTAssertFalse(APIClient.isCancellation(URLError(.timedOut)))
        XCTAssertFalse(APIClient.isCancellation(PanelError.message("cancelled")))
        XCTAssertEqual(APIClient.cacheWarning("Using expired cache (225 minutes old)"), "当前展示旧目录缓存（225 分钟前），请刷新目录或进入机型详情查询实时库存。")
    }

    @MainActor private func inventoryStore() async throws -> AppStore {
        let store = AppStore()
        await store.connect(address:"https://localhost:16443", key:"OVH-AppReview-2026")
        guard store.connection != nil else { throw XCTSkip("Local QA fixture unavailable") }
        store.selectAccount("demo-us")
        return store
    }

    @MainActor func testCancelledRefreshRetainsLastGoodDataWithoutErrorOrNewTimestamp() async throws {
        let store = try await inventoryStore()
        var cancelled = false
        let loader = NativeLoader { _,_,_,_ in
            if cancelled { throw URLError(.cancelled) }
            return APIResponse(value:.object(["price":.number(90)]), notices:["真实缓存提示"])
        }
        await loader.load("/catalog", store:store, account:"demo-us", query:["subsidiary":"US"])
        let date = loader.updated
        cancelled = true
        await loader.load("/catalog", store:store, account:"demo-us", query:["subsidiary":"US","forceRefresh":"true"])
        XCTAssertEqual(loader.value["price"].number,90)
        XCTAssertEqual(loader.updated,date)
        XCTAssertEqual(loader.notices,["真实缓存提示"])
        XCTAssertNil(loader.error); XCTAssertFalse(loader.loading)

        let market = NativeMarket { _,_ in throw URLError(.cancelled) }
        await market.load(store:store)
        XCTAssertNil(market.error); XCTAssertNil(market.updated); XCTAssertFalse(market.loading)
    }

    @MainActor func testCancelledTaskCannotPublishLateSuccessfulData() async throws {
        let store = try await inventoryStore()
        let started = expectation(description:"Read started")
        var finish: CheckedContinuation<APIResponse<JSONValue>, Never>?
        let loader = NativeLoader { _,_,_,_ in
            await withCheckedContinuation { finish = $0; started.fulfill() }
        }
        let task = Task { await loader.load("/servers", store:store, account:"demo-us") }
        await fulfillment(of:[started],timeout:5)
        task.cancel()
        finish?.resume(returning:APIResponse(value:.string("late"),notices:[]))
        await task.value
        XCTAssertEqual(loader.value,.null)
        XCTAssertNil(loader.updated); XCTAssertNil(loader.error); XCTAssertFalse(loader.loading)
    }

    @MainActor func testOlderAccountResponseCannotOverwriteNewAccount() async throws {
        let store = try await inventoryStore()
        let started = expectation(description:"US read started")
        var finish: CheckedContinuation<APIResponse<JSONValue>, Never>?
        let loader = NativeLoader { _,_,account,_ in
            if account == "demo-us" { return await withCheckedContinuation { finish = $0; started.fulfill() } }
            return APIResponse(value:.string("eu-prices"),notices:[])
        }
        let old = Task { await loader.load("/catalog",store:store,account:"demo-us",query:["subsidiary":"US"],requireActiveAccount:true) }
        await fulfillment(of:[started],timeout:5)
        store.selectAccount("demo-eu")
        await loader.load("/catalog",store:store,account:"demo-eu",query:["subsidiary":"FR"],requireActiveAccount:true)
        finish?.resume(returning:APIResponse(value:.string("us-prices"),notices:[]))
        await old.value
        XCTAssertEqual(loader.value,.string("eu-prices")); XCTAssertNil(loader.error)
    }

    @MainActor func testQueryScopeAndRealFailuresPreserveOnlyMatchingData() async throws {
        let store = try await inventoryStore()
        var failing = false
        let loader = NativeLoader { _,_,_,query in
            if failing { throw PanelError.message("价格服务暂时不可用") }
            return APIResponse(value:.string(query["subsidiary"] ?? ""),notices:[])
        }
        await loader.load("/catalog",store:store,account:"demo-us",query:["subsidiary":"US"])
        failing = true
        await loader.load("/catalog",store:store,account:"demo-us",query:["subsidiary":"US","forceRefresh":"true"])
        XCTAssertEqual(loader.value,.string("US")); XCTAssertEqual(loader.error,"价格服务暂时不可用")
        await loader.load("/catalog",store:store,account:"demo-us",query:["subsidiary":"CA"])
        XCTAssertEqual(loader.value,.null); XCTAssertNil(loader.updated)
        XCTAssertEqual(loader.error,"价格服务暂时不可用")
    }

    @MainActor func testInventoryOwnsRefreshAndCoalescesConcurrentTriggers() async throws {
        let store = try await inventoryStore()
        let started = expectation(description:"Three inventory reads started"); started.expectedFulfillmentCount = 3
        var reads = 0
        var finishPlans: CheckedContinuation<APIResponse<JSONValue>, Never>?
        var finishPrices: CheckedContinuation<APIResponse<JSONValue>, Never>?
        var finishStock: CheckedContinuation<JSONValue, Never>?
        let loader = NativeLoader { _,_,_,query in
            XCTAssertEqual(query["forceRefresh"],"true")
            XCTAssertEqual(query["showApiServers"],"true","Force refresh must fetch OVH even with the API toggle off")
            reads += 1
            return await withCheckedContinuation { finishPlans = $0; started.fulfill() }
        }
        let catalog = NativeLoader { _,_,account,query in
            XCTAssertEqual(account,"demo-us"); XCTAssertEqual(query["subsidiary"],"US")
            reads += 1
            return await withCheckedContinuation { finishPrices = $0; started.fulfill() }
        }
        let market = NativeMarket { _,_ in
            reads += 1
            return await withCheckedContinuation { finishStock = $0; started.fulfill() }
        }
        let requests = NativeInventoryRequests()
        let caller = Task { await requests.load(store:store,includeAPI:false,force:true,loader:loader,catalog:catalog,market:market) }
        await fulfillment(of:[started],timeout:5)
        caller.cancel() // The refresh control can finish/cancel while the reads are still pending.
        let joined = Task { await requests.load(store:store,includeAPI:false,loader:loader,catalog:catalog,market:market) }
        await Task.yield()
        finishPlans?.resume(returning:APIResponse(value:.string("plans"),notices:[]))
        finishPrices?.resume(returning:APIResponse(value:.string("USD"),notices:[]))
        finishStock?.resume(returning:.array([.string("US stock")]))
        await caller.value; await joined.value
        XCTAssertEqual(reads,3)
        XCTAssertEqual(loader.value,.string("plans")); XCTAssertEqual(catalog.value,.string("USD"))
        XCTAssertEqual(market.variants,[.string("US stock")]); XCTAssertNotNil(market.updated)
        XCTAssertNil(loader.error); XCTAssertNil(catalog.error); XCTAssertNil(market.error)
    }

    func testSystemMetricsUsesWebContractAndFormatsBinaryCapacity() throws {
        let data = Data("""
        {"cpu":{"percent":37.5,"cores":8},"memory":{"totalBytes":34359738368,"usedBytes":17179869184,"percent":50},"disk":{"totalBytes":2199023255552,"usedBytes":1539316278886.4,"percent":70,"path":"/"},"host":{"hostname":"qa","platform":"debian","uptimeSec":123}}
        """.utf8)
        let metrics = try JSONDecoder().decode(SystemMetrics.self, from: data)
        XCTAssertEqual(metrics.cpu.usage, 37.5)
        XCTAssertEqual(metrics.memory.usage, 50)
        XCTAssertEqual(metrics.disk.usage, 70)
        XCTAssertEqual(SystemMetrics.bytes(metrics.memory.usedBytes), "16.0 GB")
        XCTAssertEqual(SystemMetrics.bytes(metrics.disk.usedBytes), "1.4 TB")
        XCTAssertEqual(SystemMetrics.bytes(1023), "1023 B")
        XCTAssertEqual(SystemMetrics.bytes(1024), "1.0 KB")
        XCTAssertEqual(SystemMetrics.bytes(.nan), "—")
        XCTAssertEqual(ResourceTone(percent: 59.9), .normal)
        XCTAssertEqual(ResourceTone(percent: 60), .warning)
        XCTAssertEqual(ResourceTone(percent: 85), .critical)
    }

    func testMissingOrFailedMetricsNeverBecomeAnIdleMachine() throws {
        for malformed in ["{}", "{\"success\":true}", "{\"cpu\":{},\"memory\":{},\"disk\":{}}"] {
            XCTAssertThrowsError(try JSONDecoder().decode(SystemMetrics.self, from: Data(malformed.utf8)))
        }
        XCTAssertEqual(SystemMetrics.CPU(percent: 0, cores: 8).usage, 0)
        XCTAssertNil(SystemMetrics.CPU(percent: 0, cores: 0).usage)
        for invalid in [-1.0, 101, .nan, .infinity] { XCTAssertNil(SystemMetrics.validPercent(invalid)) }
        XCTAssertNil(SystemMetrics.Memory(totalBytes: 0, usedBytes: 0, percent: 0).usage)
        XCTAssertNil(SystemMetrics.Disk(totalBytes: 100, usedBytes: 101, percent: 100, path: "/").usage)
    }

    func testCatalogPricesSeparateInstallationAndUseTheirActualCurrency() throws {
        let catalog=try JSONDecoder().decode(JSONValue.self,from:Data("""
        {"locale":{"currencyCode":"CAD"},"plans":[{"planCode":"base","pricings":[{"intervalUnit":"month","interval":1,"mode":"default","price":9900000000,"tax":1000000000,"capacities":["installation"]},{"intervalUnit":"month","interval":1,"mode":"default","price":2000000000,"tax":400000000,"capacities":["renew"]}]}],"addons":[{"planCode":"ram","pricings":[{"intervalUnit":"month","interval":1,"mode":"default","price":500000000,"tax":100000000},{"mode":"default","price":300000000,"tax":60000000,"capacities":["installation"]}]}]}
        """.utf8))
        let price=try XCTUnwrap(NativePriceIndex(catalog).price(plan:"base",options:["ram"]))
        XCTAssertEqual(price.monthly,25); XCTAssertEqual(price.tax,5)
        XCTAssertEqual(price.installation,102); XCTAssertEqual(price.installationTax,10.6,accuracy:0.0001)
        XCTAssertEqual(price.currency,"CAD")
        XCTAssertNil(NativePriceIndex(catalog).price(plan:"missing",options:[]))
    }
    func testRegionalStockKeepsAvailableVariantAndMatchesAddonBoundaries() throws {
        let rows=try JSONDecoder().decode(JSONValue.self,from:Data("""
        [{"planCode":"ks","fqn":"ks.ram-128g.disk-960","datacenters":[{"datacenter":"GRA","availability":"1H"}]},{"planCode":"ks","fqn":"ks.ram-64g.disk-960","datacenters":[{"datacenter":"GRA","availability":"unavailable"},{"datacenter":"BHS","availability":"comingSoon"}]}]
        """.utf8)).array
        XCTAssertEqual(NativeMarket.index(rows)["ks"]?["gra"],"1H")
        XCTAssertEqual(NativeMarket.index(rows)["ks"]?["bhs"],"comingSoon")
        XCTAssertEqual(NativeMarket.optionAvailable("ram-128g-ks",variants:rows,plan:"ks"),true)
        XCTAssertEqual(NativeMarket.optionAvailable("ram-1",variants:rows,plan:"ks"),false)
        XCTAssertNil(NativeMarket.optionAvailable("ram",variants:rows,plan:"unknown"))
    }
    func testNativeTrafficPreservesOVHUnitsAndMissingValues() throws {
        let data=Data("""
        {"interfaces":[{"mac":"public","data":[{"timestamp":200,"value":{"value":3000000,"unit":"bps"}},{"timestamp":100,"value":{"value":1000000,"unit":"bps"}},{"timestamp":300,"value":null}]},{"mac":"private","data":[{"timestamp":100,"value":{"value":9000000,"unit":"bps"}}]}]}
        """.utf8)
        let json=try JSONDecoder().decode(JSONValue.self,from:data)
        let points=NativeTrafficPoint.decode(json,mac:"public",metric:"traffic",direction:"下载")
        XCTAssertEqual(points.map(\.value),[1,3])
        XCTAssertEqual(points.map { $0.date.timeIntervalSince1970 },[100,200])
        XCTAssertEqual(NativeTrafficPoint.decode(json,mac:"public",metric:"packets",direction:"上传").map(\.value),[1000000,3000000])
        XCTAssertTrue(NativeTrafficPoint.decode(json,mac:"missing",metric:"traffic",direction:"下载").isEmpty)
    }
    func testNativeOperationPathAndQueryEscapeWithoutAccountOverride() throws {
        let update=NativeCatalog.shared.operation("PUT","/accounts/:id")
        let (_,_,body)=try update.resolve(values:["proxyUrl":.string("")],context:.init(account:"eu",accountName:"EU",bindings:["id":.string("eu")]))
        XCTAssertEqual(body?["proxyUrl"],.string(""),"An explicitly cleared proxy must be sent, so the backend restores direct routing")
        XCTAssertNil(body?.object["appSecret"],"Untouched masked credentials must not be posted")
        let c = try Connection.validated(address: "https://panel.example", key: "test")
        let client = APIClient(connection: c)
        let service = "svc/with?#spaces 中文"
        let request = client.makeRequest("/server-control/" + APIClient.component(service) + "/mrtg?account=wrong&type=traffic:download", account: "right account", query: ["period":"daily"])
        let parts = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertTrue(parts.percentEncodedPath.contains("svc%2Fwith%3F%23spaces%20"))
        XCTAssertEqual(parts.queryItems?.filter { $0.name == "account" }.map(\.value), ["right account"])
        XCTAssertEqual(parts.queryItems?.first { $0.name == "type" }?.value, "traffic:download")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "period" }?.value, "daily")
    }

    func testVPSRebuildUsesStringImageIDAndNativeStorageUsesRealSchema() throws {
        let catalog = NativeCatalog.shared
        let vps = catalog.operation("POST", "/vps-control/:service_name/reinstall")
        let context = NativeContext(account: "us", accountName: "US", service: "vps.example")
        let (_,_,body) = try vps.resolve(values: ["templateId":.string("debian13-image-uuid"),"sshKey":.array([.string("my-key")])], context: context)
        XCTAssertEqual(body?["templateId"], .string("debian13-image-uuid"))
        XCTAssertThrowsError(try vps.resolve(values: [:], context: context))
        let install = catalog.operation("POST", "/server-control/:service_name/install")
        let storage = try XCTUnwrap(install.fields.first { $0.key == "storageConfig" })
        let partitioning = try XCTUnwrap(storage.children?.first { $0.key == "partitioning" })
        XCTAssertEqual(partitioning.kind, "object")
        let layout = try XCTUnwrap(partitioning.children?.first { $0.key == "layout" })
        XCTAssertTrue(layout.children?.contains { $0.key == "mountPoint" } == true)
        XCTAssertTrue(layout.children?.contains { $0.key == "fileSystem" } == true)
        let raid = try XCTUnwrap(storage.children?.first { $0.key == "hardwareRaid" })
        XCTAssertEqual(raid.children?.first { $0.key == "disks" }?.kind, "number")
    }

    func testNoUnknownEnumsOrLostTerminationModes() throws {
        let rescue = NativeCatalog.shared.operation("POST", "/server-control/:service_name/rescue")
        XCTAssertEqual(rescue.fields.first { $0.key == "sshKey" }?.kind,"text")
        let rebuild = NativeCatalog.shared.operation("POST", "/vps-control/:service_name/reinstall")
        XCTAssertEqual(rebuild.fields.first { $0.key == "sshKey" }?.kind,"list")
        let end = NativeCatalog.shared.operation("PUT", "/server-control/:service_name/engagement/end-rule")
        XCTAssertEqual(Set(end.fields.first { $0.key == "strategy" }?.choices ?? []), Set(["CANCEL_SERVICE","REACTIVATE_ENGAGEMENT","STOP_ENGAGEMENT_FALLBACK_DEFAULT_PRICE","STOP_ENGAGEMENT_KEEP_PRICE"]))
        let policy = NativeCatalog.shared.operation("PUT", "/vps-control/:service_name/termination-policy")
        XCTAssertEqual(Set(policy.fields.first { $0.key == "policy" }?.choices ?? []), Set(["empty","terminateAtExpirationDate","terminateAtEngagementDate"]))
        let spla = NativeCatalog.shared.operation("POST", "/server-control/:service_name/spla")
        XCTAssertEqual(spla.fields.first { $0.key == "type" }?.choices, ["os","sqlstd","sqlweb"])
    }

    func testOnlyConfirmedAvailabilityIsOrderable() {
        for status in ["1H","72H","24H-high","240H-low"] { XCTAssertTrue(NativeStock.orderable(status)) }
        for status in ["comingSoon","unavailable","unknown","", "1H-maybe"] { XCTAssertFalse(NativeStock.orderable(status)) }
    }

    func testTaskActionsKeepTheirActualAccountAndTaskID() throws {
        let op = NativeCatalog.shared.operation("/server-control/:service_name/tasks")
        let record: JSONValue = .object(["taskId":.number(42),"function":.string("maintenance")])
        let context = NativeContext(account: "original-eu", accountName: "EU", service: "server.example")
        let actions = NativeActionRelations.actions(for: op, record: record, context: context)
        let action = try XCTUnwrap(actions.first { $0.0.path.hasSuffix("/schedule") })
        XCTAssertEqual(action.1.account, "original-eu")
        XCTAssertEqual(action.1.bindings["task_id"], .number(42))
        let (path,_,_) = try action.0.resolve(values: [:], context: action.1)
        XCTAssertEqual(path, "/server-control/server.example/tasks/42/schedule")
    }

    func testCountryCurrencyAndAPIRegionsMatchWebSource() {
        XCTAssertEqual(NativeCatalog.shared.subsidiaries.count, 24)
        for (zone, endpoint, currency) in [("WE","ovh-ca","USD"),("US","ovh-us","USD"),("GB","ovh-eu","GBP"),("SG","ovh-ca","SGD"),("MA","ovh-eu","MAD")] {
            let a = OVHAccount(id: zone, name: zone, endpoint: endpoint, zone: zone, isDefault: false)
            XCTAssertEqual(a.currency,currency)
            XCTAssertEqual(NativeCatalog.shared.subsidiaries.first { $0.code == zone }?.endpoint,endpoint)
        }
    }

    func testAllNativeDescriptorsHaveValidAndDistinctInputLocations() throws {
        let operations = NativeCatalog.shared.operations
        XCTAssertEqual(operations.count,226)
        XCTAssertEqual(Set(operations.map(\.id)).count,operations.count)
        for op in operations {
            XCTAssertEqual(Set(op.fields.map(\.id)).count,op.fields.count,op.id)
            XCTAssertTrue(op.fields.allSatisfy { ["path","query","body"].contains($0.location) },op.id)
            XCTAssertFalse(op.path.hasPrefix("/internal/"))
        }
    }

    func testNativeSettingsAndMonitoringPreserveExistingDataAgainstFixture() async throws {
        let client = APIClient(connection: try Connection.validated(address: "https://localhost:16443", key: "OVH-AppReview-2026"))
        let original: JSONValue
        do { original = try await client.value("/settings").value } catch { throw XCTSkip("Local QA fixture unavailable: " + error.localizedDescription) }
        var next = original.object; next["defaultRetryInterval"] = .number(75)
        _ = try await client.value("/settings", method: "POST", body: .object(next))
        let saved = try await client.value("/settings").value
        XCTAssertEqual(saved["tgToken"], original["tgToken"])
        XCTAssertEqual(saved["consumerKey"], original["consumerKey"])
        let before = try await client.value("/monitor/subscriptions").value.array[0]
        _ = try await client.value("/monitor/subscriptions/24ks-le-b", method: "PUT", body: .object(["quantity":.number(2)]))
        let after = try await client.value("/monitor/subscriptions").value.array[0]
        XCTAssertEqual(after["lastStatus"], before["lastStatus"])
        XCTAssertEqual(after["datacenters"], before["datacenters"])
        XCTAssertEqual(after["options"], before["options"])
        _ = try await client.value("/settings",method:"POST",body:original)
    }
    func testPairingQRMatchesUpstreamFragmentContract() throws {
        let input = try PairingInput.fromQRCode("https://panel.example:8443/api/app/pair#abcd-2345")
        XCTAssertEqual(input.address, "https://panel.example:8443")
        XCTAssertEqual(input.code, "ABCD2345")
        XCTAssertEqual(try PairingInput.fromQRCode("http://panel.example/api/app/pair#ABCD2345").address, "https://panel.example")
        for bad in ["https://user:pass@panel.example/api/app/pair#ABCD2345", "https://panel.example/wrong#ABCD2345", "https://panel.example/api/app/pair?token=x#ABCD2345", "javascript:alert(1)", "https://panel.example/api/app/pair#INVALID!"] {
            XCTAssertThrowsError(try PairingInput.fromQRCode(bad))
        }
    }

    func testPairingRequestNeverIncludesExistingCredentialsOrCodeInURL() throws {
        let request = try APIClient.pairingRequest(address: "https://panel.example", code: "abcd2345", deviceName: "Test iPhone")
        XCTAssertEqual(request.url?.absoluteString, "https://panel.example/api/app/pair")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-API-Key"))
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(body, ["code": "ABCD2345", "deviceName": "Test iPhone"])
        XCTAssertThrowsError(try APIClient.pairingRequest(address: "http://panel.example", code: "ABCD2345", deviceName: "iPhone"))
        XCTAssertThrowsError(try APIClient.pairingRequest(address: "https://panel.example", code: "ABC", deviceName: "iPhone"))
    }

    func testLegacyKeychainMigrationAndExclusiveDeviceAuthentication() throws {
        let legacy = try JSONDecoder().decode(Connection.self, from: Data("{\"address\":\"https://panel.example\",\"key\":\"legacy\"}".utf8))
        XCTAssertEqual(legacy.authentication, .apiKey)
        let legacyRequest = APIClient(connection: legacy).makeRequest("/accounts")
        XCTAssertEqual(legacyRequest.value(forHTTPHeaderField: "X-API-Key"), "legacy")
        XCTAssertNil(legacyRequest.value(forHTTPHeaderField: "Authorization"))
        let paired = try Connection.validated(address: legacy.address, key: "device", authentication: .deviceToken, deviceID: 7)
        XCTAssertEqual(try JSONDecoder().decode(Connection.self, from: JSONEncoder().encode(paired)), paired)
        let request = APIClient(connection: paired).makeRequest("/vps-control/list", account: "us account")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer device")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-API-Key"))
        XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "us account")
    }

    func testActualQRCodeImageDecodesToPairingOriginAndCode() throws {
        let text = "https://panel.example/api/app/pair#ABCD2345"
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": Data(text.utf8), "inputCorrectionLevel": "M"]))
        let image = try XCTUnwrap(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let cgImage = try XCTUnwrap(CIContext().createCGImage(image, from: image.extent))
        let png = try XCTUnwrap(UIImage(cgImage: cgImage).pngData())
        let decoded = try PairingQRCodeReader.read(png)
        XCTAssertEqual(decoded, text)
        XCTAssertEqual(try PairingInput.fromQRCode(decoded).code, "ABCD2345")
        XCTAssertThrowsError(try PairingQRCodeReader.read(Data("not an image".utf8)))
    }

    func testRejectsCredentialURLsAndInsecureOrigins() {
        for address in ["http://example.com", "https://user:pass@example.com", "https://example.com/?key=secret", "https://example.com/panel", "https://example.com/#fragment"] {
            XCTAssertThrowsError(try Connection.validated(address: address, key: "key"))
        }
        XCTAssertThrowsError(try Connection.validated(address: "https://example.com", key: "  "))
        XCTAssertEqual(try Connection.validated(address: " https://example.com/ ", key: " key ").address, "https://example.com")
    }

    func testPartialAssetsRetainUnknownRenewalAndFailure() throws {
        let json = """
        {"servers":[{"serviceName":"unavailable-server","renewalType":null,"error":"fetch failed"}]}
        """
        let data = try JSONDecoder().decode(DedicatedResponse.self, from: Data(json.utf8))
        let asset = Asset(data.servers[0])
        XCTAssertNil(asset.renewal)
        XCTAssertEqual(asset.stateLabel, "状态未知")
        XCTAssertFalse(asset.healthy)
        XCTAssertEqual(asset.issue, "fetch failed")
    }

    func testDecodesUSVPSAndIndependentRegions() throws {
        let json = """
        {"vps":[{"serviceName":"example.vps.ovh.us","displayName":"US-097","state":"running","zone":"Region OpenStack: os-us-west-or-2","vcore":1,"memoryMB":2048,"diskGB":20,"renewalType":true}]}
        """
        let data = try JSONDecoder().decode(VPSResponse.self, from: Data(json.utf8))
        let asset = Asset(data.vps[0])
        XCTAssertEqual(asset.name, "US-097")
        XCTAssertEqual(asset.location, "俄勒冈 · 美国")
        XCTAssertEqual(asset.specification, "1 vCPU · 2 GB · 20 GB")
        XCTAssertEqual(OVHAccount(id: "we", name: "WE", endpoint: "ovh-ca", zone: "WE", isDefault: true).region, "CA")
        XCTAssertEqual(OVHAccount(id: "us", name: "US", endpoint: "ovh-us", zone: "US", isDefault: false).region, "US")
    }
}
