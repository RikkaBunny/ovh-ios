import XCTest

final class OVHPocketUITests: XCTestCase {
    private func nativeApp(dark: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["OVH_NATIVE_QA":"1","OVH_BOOTSTRAP_ADDRESS":"https://localhost:16443","OVH_BOOTSTRAP_KEY":"OVH-AppReview-2026"]
        app.launchArguments = ["-nativeAppearance",dark ? "dark" : "light"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["account.menu"].waitForExistence(timeout: 60))
        return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<10 { if element.isHittable { return }; app.swipeUp() }
    }
    private func waitForOrientation(_ app:XCUIApplication, landscape:Bool) {
        let earliest=Date().addingTimeInterval(1)
        let settled=expectation(for:NSPredicate { _,_ in
            let size=app.windows.firstMatch.frame.size
            return Date() >= earliest && (landscape ? size.width > size.height : size.height > size.width)
        },evaluatedWith:app)
        wait(for:[settled],timeout:10)
    }
    func testNativeCatalogQueueAndMonitor() throws {
        let app = nativeApp()
        save(app,name:"Native-01-Dashboard")
        app.buttons["tab.more"].tap(); app.buttons["more.servers"].tap()
        let plan = app.buttons["plan.24ks-le-b"]
        XCTAssertTrue(plan.waitForExistence(timeout:30))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","20.83")).firstMatch.waitForExistence(timeout:10))
        save(app,name:"Native-02-Catalog")
        plan.tap()
        let order=app.buttons["plan.order"]; reveal(order,app:app); order.tap()
        XCTAssertTrue(app.staticTexts["下单账户：欧洲演示账户"].waitForExistence(timeout:10))
        let dc=app.switches["GRA"]; XCTAssertTrue(dc.exists); dc.tap()
        let submit=app.buttons["order.submit"]; reveal(submit,app:app); XCTAssertTrue(submit.isEnabled); submit.tap()
        XCTAssertTrue(app.buttons["确认创建"].waitForExistence(timeout:10)); app.buttons["取消"].tap()
        XCTAssertFalse(app.webViews.firstMatch.exists)
        submit.tap(); app.buttons["确认创建"].tap()
        XCTAssertTrue(app.staticTexts["任务已创建，后端会持续尝试下单。"].waitForExistence(timeout:30)); save(app,name:"Native-03-Order")
        app.buttons["tab.queue"].tap()
        XCTAssertTrue(app.staticTexts["24ks-le-b"].firstMatch.waitForExistence(timeout:30)); save(app,name:"Native-04-Queue")
        app.buttons["tab.monitor"].tap()
        XCTAssertTrue(app.staticTexts["KS-LE-B"].firstMatch.waitForExistence(timeout:30)); save(app,name:"Native-05-Monitor")
        let monitorRow=app.buttons.containing(.staticText,identifier:"KS-LE-B").firstMatch; monitorRow.tap()
        let edit=app.buttons["native.UpdateSubscription"]; reveal(edit,app:app); XCTAssertTrue(edit.exists); edit.tap()
        XCTAssertTrue(app.otherElements["field.notifyAvailable"].waitForExistence(timeout:10) || app.switches.firstMatch.exists)
        save(app,name:"Native-06-SubscriptionForm")
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }
    func testNativeAssetsAdvancedAndHistory() throws {
        let app=nativeApp()
        app.buttons["tab.servers"].tap()
        save(app,name:"Native-Diagnostic-AssetsEntry")
        let server=app.buttons["asset.ns-demo-eu.example"]
        if !server.waitForExistence(timeout:10) { print(app.debugDescription); XCTFail("Native asset entry did not open"); return }; server.tap()
        XCTAssertTrue(app.staticTexts["处理器"].waitForExistence(timeout:30)); save(app,name:"Native-07-ServerOverview")
        let chart=app.descendants(matching:.any)["traffic.chart"]; reveal(chart,app:app)
        XCTAssertTrue(chart.exists); XCTAssertTrue(app.staticTexts["峰值"].firstMatch.exists); save(app,name:"Native-22-Traffic")
        for _ in 0..<5 { if app.segmentedControls["detail.tabs"].frame.minY > 130 && app.segmentedControls["detail.tabs"].isHittable { break }; app.scrollViews.firstMatch.swipeDown() }
        let tabs=app.segmentedControls["detail.tabs"]
        tabs.buttons["电源"].tap()
        XCTAssertTrue(app.buttons["native.Reboot"].waitForExistence(timeout:10))
        app.buttons["native.Reboot"].tap()
        app.buttons["operation.submit"].tap()
        XCTAssertTrue(app.staticTexts["确认操作"].waitForExistence(timeout:10)); app.buttons["取消"].tap()
        XCTAssertFalse(app.webViews.firstMatch.exists)
        app.buttons["navigation.back"].tap(); tabs.buttons["维护"].tap(); save(app,name:"Native-08-Maintenance")
        tabs.buttons["高级"].tap(); app.buttons["FTP 备份"].firstMatch.tap(); save(app,name:"Native-09-Advanced")
        XCTAssertTrue(app.buttons["native.GetBackupFTP"].exists)
        app.buttons["tab.more"].tap()
        for _ in 0..<3 { if app.buttons["more.history"].isHittable { break }; if app.buttons["navigation.back"].exists { app.buttons["navigation.back"].tap() } }
        app.buttons["more.history"].tap()
        XCTAssertTrue(app.staticTexts["24ks-le-b"].firstMatch.waitForExistence(timeout:30)); save(app,name:"Native-10-History")
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }
    func testNativeSettingsScrollDarkAndDisconnect() throws {
        let app=nativeApp(dark:true)
        app.buttons["tab.more"].tap(); save(app,name:"Native-11-More-Dark")
        app.buttons["more.connection"].tap()
        save(app,name:"Native-Diagnostic-ConnectionEntry")
        let disconnect=app.buttons["settings.disconnect"]; reveal(disconnect,app:app)
        XCTAssertTrue(disconnect.isHittable)
        let steady=expectation(for:NSPredicate { _,_ in !disconnect.isHittable },evaluatedWith:app); steady.isInverted=true; wait(for:[steady],timeout:3)
        save(app,name:"Native-12-Settings-Dark")
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForOrientation(app,landscape:true)
        reveal(disconnect,app:app); XCTAssertTrue(disconnect.isHittable); save(app,name:"Native-13-Landscape")
        XCUIDevice.shared.orientation = .portrait
        waitForOrientation(app,landscape:false)
        reveal(disconnect,app:app); disconnect.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout:10)); app.alerts.buttons["取消"].tap()
        XCTAssertTrue(disconnect.isHittable)
        disconnect.tap(); app.alerts.buttons["断开并移除本机凭据"].tap()
        XCTAssertTrue(app.buttons["pairing.scan"].waitForExistence(timeout:10)); save(app,name:"Native-14-Pairing")
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }

    func testNativeRegionsVPSSnapshotAndReinstallForm() throws {
        let app=nativeApp()
        app.buttons["tab.servers"].tap(); app.buttons["assets.filter.vps"].tap()
        app.buttons["account.menu"].tap(); app.buttons["account.US"].tap()
        let vps=app.buttons["asset.vps-demo-us.example"]
        XCTAssertTrue(vps.waitForExistence(timeout:30)); vps.tap()
        XCTAssertTrue(app.staticTexts["操作系统"].firstMatch.waitForExistence(timeout:30))
        let tabs=app.segmentedControls["detail.tabs"]
        tabs.buttons["快照"].tap()
        XCTAssertTrue(app.staticTexts["安装前备份"].waitForExistence(timeout:10)); save(app,name:"Native-15-VPSSnapshot")
        tabs.buttons["电源"].tap(); let templates=app.buttons["native.GetVpsTemplates"]; reveal(templates,app:app); templates.tap()
        let reinstall=app.buttons["native.ReinstallVps"].firstMatch
        XCTAssertTrue(reinstall.waitForExistence(timeout:10)); reveal(reinstall,app:app); reinstall.tap()
        let image=app.textFields["input.templateId"]
        XCTAssertTrue(image.waitForExistence(timeout:10)); XCTAssertEqual(image.value as? String,"debian-13-image")
        let submit=app.buttons["operation.submit"]; reveal(submit,app:app); submit.tap()
        let confirm=app.buttons["operation.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout:10)); XCTAssertFalse(confirm.isEnabled)
        XCTAssertTrue(app.staticTexts["美国演示账户"].exists); save(app,name:"Native-16-ReinstallConfirmation")
        app.buttons["取消"].tap()
        for _ in 0..<4 { if app.buttons["account.menu"].exists { break }; app.buttons["navigation.back"].tap() }
        app.buttons["account.menu"].tap(); app.buttons["account.CA"].tap()
        app.buttons["tab.servers"].tap()
        for _ in 0..<6 { if app.buttons["assets.filter.all"].exists { break }; app.buttons["navigation.back"].tap() }
        app.buttons["assets.filter.all"].tap()
        XCTAssertTrue(app.buttons["asset.ns-demo-ca.example"].waitForExistence(timeout:30))
        XCTAssertFalse(app.buttons["asset.ns-demo-eu.example"].exists)
        save(app,name:"Native-17-Canada")
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }

    @MainActor func testNativeSettingsSaveAndDevicePairing() async throws {
        let app=nativeApp()
        _=try await fixture("/accounts/demo-eu",method:"PUT",body:["proxyUrl":"http://qa-proxy.invalid:8080"])
        app.buttons["tab.more"].tap(); app.buttons["more.settings"].tap()
        let editAccount=app.buttons["native.UpdateAccount"].firstMatch; reveal(editAccount,app:app); editAccount.tap()
        let proxy=app.textFields["input.proxyUrl"]; reveal(proxy,app:app)
        guard proxy.waitForExistence(timeout:10) else { XCTFail("Account proxy form did not load"); return }
        XCTAssertEqual(proxy.value as? String,"http://qa-proxy.invalid:8080")
        proxy.tap(); proxy.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:0.5)).tap(); proxy.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:32))
        save(app,name:"Native-23-ProxyClearedForm")
        let accountSave=app.buttons["operation.submit"]; reveal(accountSave,app:app); accountSave.tap()
        guard app.buttons["operation.confirm"].waitForExistence(timeout:10) else { XCTFail("Account confirmation did not open"); return }; app.buttons["operation.confirm"].tap()
        XCTAssertTrue(app.staticTexts["请求已成功提交"].waitForExistence(timeout:10))
        let cleared=try await fixture("/accounts/demo-eu"); guard cleared["proxyUrl"] as? String == "" else { XCTFail("Proxy clearing was not applied"); return }
        app.buttons["navigation.back"].tap()
        let settings=app.buttons["native.SaveSettings"]; reveal(settings,app:app); settings.tap()
        let interval=app.descendants(matching:.any)["input.defaultRetryInterval"]; reveal(interval,app:app)
        guard interval.waitForExistence(timeout:10) else { save(app,name:"Native-Diagnostic-SettingsForm"); print(app.debugDescription); XCTFail("Missing interval input"); return }; interval.tap()
        let old=interval.value as? String ?? ""
        interval.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.count)+"90\n")
        let submit=app.buttons["operation.submit"]; reveal(submit,app:app); submit.tap()
        guard app.buttons["operation.confirm"].waitForExistence(timeout:10) else { XCTFail("Confirmation did not open"); return }; app.buttons["operation.confirm"].tap()
        XCTAssertTrue(app.staticTexts["请求已成功提交"].waitForExistence(timeout:10)); save(app,name:"Native-18-SettingsSaved")
        let saved=try await fixture("/settings")
        XCTAssertEqual(saved["defaultRetryInterval"] as? Int,90)
        XCTAssertEqual(saved["consumerKey"] as? String,"qa-consumer")
        app.buttons["navigation.back"].tap()
        let generate=app.buttons["native.CreatePairingCode"]; reveal(generate,app:app); generate.tap()
        app.buttons["operation.submit"].tap(); app.buttons["operation.confirm"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","有效期剩余")).firstMatch.waitForExistence(timeout:10)); save(app,name:"Native-19-PairingCode")
        // Pair a synthetic device using the real one-time-code contract.
        let code=try await fixture("/app/pairing-codes",method:"POST")["code"] as! String
        for _ in 0..<3 { if app.buttons["more.connection"].exists { break }; app.buttons["navigation.back"].tap() }
        app.buttons["more.connection"].tap()
        let disconnect=app.buttons["settings.disconnect"]; reveal(disconnect,app:app); disconnect.tap(); app.alerts.buttons["断开并移除本机凭据"].tap()
        XCTAssertTrue(app.textFields["pairing.address"].waitForExistence(timeout:10))
        let address=app.textFields["pairing.address"]; address.tap()
        let previous=address.value as? String ?? ""
        address.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:previous.count)+"https://localhost:16443")
        app.textFields["pairing.code"].tap(); app.textFields["pairing.code"].typeText(code+"\n")
        let pair=app.buttons["pairing.submit"]; reveal(pair,app:app); pair.tap()
        XCTAssertTrue(app.buttons["account.menu"].waitForExistence(timeout:30)); save(app,name:"Native-20-DevicePaired")
        app.terminate(); app.launchEnvironment=[:]; app.launch()
        XCTAssertTrue(app.buttons["account.menu"].waitForExistence(timeout:30))
        let devices=try await fixture("/app/devices")["devices"] as! [[String:Any]]
        XCTAssertEqual(devices.count,1)
        _=try await fixture("/app/devices/\(devices[0]["id"]!)",method:"DELETE")
        app.buttons["tab.servers"].tap()
        XCTAssertTrue(app.buttons["pairing.scan"].waitForExistence(timeout:30)); save(app,name:"Native-21-RevokedDevice")
    }

    private func fixture(_ path:String,method:String="GET",body:[String:Any]?=nil) async throws -> [String:Any] {
        var request=URLRequest(url:URL(string:"https://localhost:16443/api"+path)!)
        request.httpMethod=method; request.setValue("OVH-AppReview-2026",forHTTPHeaderField:"X-API-Key")
        if let body { request.httpBody=try JSONSerialization.data(withJSONObject:body); request.setValue("application/json",forHTTPHeaderField:"Content-Type") }
        let (data,response)=try await URLSession.shared.data(for:request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200)
        return try JSONSerialization.jsonObject(with:data) as! [String:Any]
    }

    override func tearDown() async throws {
        _ = try await fixture("/qa/refresh",method:"POST",body:[:])
        _ = try await fixture("/qa/inventory",method:"POST",body:[:])
        _ = try await fixture("/qa/metrics",method:"POST",body:["mode":"ok"])
        try await super.tearDown()
    }

    @MainActor private func pull(_ app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        let start = scroll.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.15))
        start.press(forDuration:0.1, thenDragTo:scroll.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.85)))
    }

    @MainActor func testDashboardAndInstancesSlowPullReallyUpdateData() async throws {
        _ = try await fixture("/qa/refresh",method:"POST",body:[:])
        let app = nativeApp(dark:true)
        XCTAssertTrue(app.staticTexts["2"].waitForExistence(timeout:10))
        _ = try await fixture("/qa/refresh",method:"POST",body:["delay":2,"marker":91])
        pull(app)
        XCTAssertTrue(app.staticTexts["91"].waitForExistence(timeout:15),"The dashboard must receive new statistics after the gesture ends")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS[c] %@","cancelled")).firstMatch.exists)
        save(app,name:"Build9-01-DashboardPull")
        _ = try await fixture("/qa/refresh",method:"POST",body:[:])
        app.buttons["tab.servers"].tap()
        XCTAssertTrue(app.buttons["asset.ns-demo-eu.example"].waitForExistence(timeout:10))
        let ready = expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:app.buttons["assets.refresh"])
        await fulfillment(of:[ready],timeout:10)
        _ = try await fixture("/qa/refresh",method:"POST",body:["delay":2,"marker":92])
        pull(app)
        XCTAssertTrue(app.staticTexts["欧洲独立服务器-refresh-92"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["EU 开发环境-refresh-92"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS[c] %@","cancelled")).firstMatch.exists)
        save(app,name:"Build9-02-InstancesPull")
    }

    @MainActor func testInstanceFailureKeepsLastGoodDataAndRetryRecovers() async throws {
        _ = try await fixture("/qa/refresh",method:"POST",body:[:])
        let app = nativeApp()
        app.buttons["tab.servers"].tap()
        XCTAssertTrue(app.buttons["asset.ns-demo-eu.example"].waitForExistence(timeout:10))
        let ready = expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:app.buttons["assets.refresh"])
        await fulfillment(of:[ready],timeout:10)
        _ = try await fixture("/qa/refresh",method:"POST",body:["mode":"error","delay":1])
        pull(app)
        let error = app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","QA refresh temporarily unavailable")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["asset.ns-demo-eu.example"].exists)
        XCTAssertTrue(app.buttons["asset.vps-demo-eu.example"].exists)
        save(app,name:"Build9-03-InstancesFailureRetainsData")
        _ = try await fixture("/qa/refresh",method:"POST",body:["delay":1,"marker":93])
        app.buttons["assets.refresh"].tap()
        XCTAssertTrue(app.staticTexts["欧洲独立服务器-refresh-93"].waitForExistence(timeout:10))
        XCTAssertFalse(error.exists)
    }

    @MainActor func testInstanceRefreshSwitchAccountAndForeground() async throws {
        _ = try await fixture("/qa/refresh",method:"POST",body:[:])
        let app = nativeApp()
        app.buttons["tab.servers"].tap()
        XCTAssertTrue(app.buttons["asset.ns-demo-eu.example"].waitForExistence(timeout:10))
        let ready = expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:app.buttons["assets.refresh"])
        await fulfillment(of:[ready],timeout:10)
        _ = try await fixture("/qa/refresh",method:"POST",body:["delay":2,"marker":94])
        pull(app)
        app.buttons["account.menu"].tap(); app.buttons["account.US"].tap()
        XCTAssertTrue(app.staticTexts["US 云主机-refresh-94"].waitForExistence(timeout:15))
        XCTAssertFalse(app.buttons["asset.ns-demo-eu.example"].exists)
        XCTAssertFalse(app.buttons["asset.vps-demo-eu.example"].exists)
        XCUIDevice.shared.press(.home); app.activate()
        let returned = expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:app.buttons["assets.refresh"])
        await fulfillment(of:[returned],timeout:15)
        XCTAssertTrue(app.buttons["asset.vps-demo-us.example"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS[c] %@","cancelled")).firstMatch.exists)
        save(app,name:"Build9-04-InstanceAccountAndForeground")
    }

    @MainActor func testDetailAndLogsSlowPullUpdateReadResults() async throws {
        _ = try await fixture("/qa/refresh",method:"POST",body:[:])
        let app = nativeApp()
        app.buttons["tab.servers"].tap(); app.buttons["asset.ns-demo-eu.example"].tap()
        XCTAssertTrue(app.staticTexts["Intel Xeon E3-1230 v6"].waitForExistence(timeout:10))
        _ = try await fixture("/qa/refresh",method:"POST",body:["delay":2,"marker":95])
        pull(app)
        XCTAssertTrue(app.staticTexts["QA CPU refresh 95"].waitForExistence(timeout:15))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS[c] %@","cancelled")).firstMatch.exists)
        save(app,name:"Build9-05-DetailPull")
        _ = try await fixture("/qa/refresh",method:"POST",body:[:])
        app.buttons["navigation.back"].tap(); app.buttons["tab.more"].tap()
        let logs = app.buttons["more.logs"]; reveal(logs,app:app); logs.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","GRA 库存")).firstMatch.waitForExistence(timeout:10))
        _ = try await fixture("/qa/refresh",method:"POST",body:["delay":2,"marker":96])
        pull(app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","QA log refresh 96")).firstMatch.waitForExistence(timeout:15))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS[c] %@","cancelled")).firstMatch.exists)
        save(app,name:"Build9-06-LogsPull")
    }

    @MainActor func testCatalogSlowPullToRefreshDoesNotCancelRequests() async throws {
        _ = try await fixture("/qa/inventory", method:"POST", body:["delay":2])
        let app = nativeApp(dark:true)
        app.buttons["account.menu"].tap(); app.buttons["account.US"].tap()
        app.buttons["tab.more"].tap(); app.buttons["more.servers"].tap()
        XCTAssertTrue(app.buttons["plan.24ks-le-b"].waitForExistence(timeout:20))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "20.83")).firstMatch.waitForExistence(timeout:10))
        let scroll = app.scrollViews.firstMatch
        let start = scroll.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.15))
        start.press(forDuration:0.1, thenDragTo:scroll.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.85)))
        let settled = expectation(description:"Slow refresh responses finish")
        DispatchQueue.main.asyncAfter(deadline:.now()+4) { settled.fulfill() }
        await fulfillment(of:[settled], timeout:6)
        let state = try await fixture("/qa/inventory")
        XCTAssertGreaterThan(state["forced"] as? Int ?? 0,0,"The gesture must really request a forced refresh")
        save(app,name:"Catalog-Cancellation-Regression")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS[c] %@", "cancelled")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "20.83")).firstMatch.exists)
        _ = try await fixture("/qa/inventory", method:"POST", body:[:])
    }

    @MainActor func testExpiredCatalogAndRealNetworkFailureRecoverOnRefresh() async throws {
        _ = try await fixture("/qa/inventory", method:"POST", body:["mode":"expired","delay":0.5])
        let app = nativeApp(dark:true)
        app.buttons["account.menu"].tap(); app.buttons["account.US"].tap()
        app.buttons["tab.more"].tap(); app.buttons["more.servers"].tap()
        let oldCache = app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "225 分钟前"))
        XCTAssertTrue(oldCache.firstMatch.waitForExistence(timeout:15))
        XCTAssertEqual(oldCache.count,1)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "Using expired cache")).firstMatch.exists)
        save(app,name:"Build8-01-SingleCacheWarning")
        _ = try await fixture("/qa/inventory", method:"POST", body:["mode":"error","delay":0.5])
        app.buttons["servers.refresh"].tap()
        let realError = app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "QA catalog temporarily unavailable")).firstMatch
        XCTAssertTrue(realError.waitForExistence(timeout:10),"Genuine server failures must remain visible")
        XCTAssertTrue(app.buttons["plan.24ks-le-b"].exists,"The last successful catalog remains usable")
        save(app,name:"Build8-02-RealNetworkFailure")
        _ = try await fixture("/qa/inventory", method:"POST", body:["delay":0.5])
        let ready = expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:app.buttons["servers.refresh"])
        await fulfillment(of:[ready],timeout:10)
        app.buttons["servers.refresh"].tap()
        let recovered = expectation(for:NSPredicate { _,_ in
            !realError.exists && !oldCache.firstMatch.exists && app.staticTexts["servers.stockUpdated"].exists && app.buttons["servers.refresh"].isEnabled
        },evaluatedWith:app)
        await fulfillment(of:[recovered],timeout:15)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS[c] %@", "cancelled")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "US$20.83")).firstMatch.exists)
        save(app,name:"Build8-03-FreshUSCatalog")
        _ = try await fixture("/qa/inventory", method:"POST", body:[:])
    }

    @MainActor func testPendingCatalogSwitchesRegionAndReturnsFromBackground() async throws {
        _ = try await fixture("/qa/inventory",method:"POST",body:["delay":3])
        let app = nativeApp()
        app.buttons["account.menu"].tap(); app.buttons["account.EU"].tap()
        app.buttons["tab.more"].tap(); app.buttons["more.servers"].tap()
        app.buttons["account.menu"].tap(); app.buttons["account.CA"].tap()
        app.buttons["account.menu"].tap(); app.buttons["account.US"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "US$20.83")).firstMatch.waitForExistence(timeout:20))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS[c] %@", "cancelled")).firstMatch.exists)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["plan.24ks-le-b"].waitForExistence(timeout:20))
        let ready = expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:app.buttons["servers.refresh"])
        await fulfillment(of:[ready],timeout:15)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS[c] %@", "cancelled")).firstMatch.exists)
        save(app,name:"Build8-04-RegionAndForeground")
        _ = try await fixture("/qa/inventory",method:"POST",body:[:])
    }

    @MainActor func testDashboardResourceFailureAndRecovery() async throws {
        _ = try await fixture("/qa/refresh",method:"POST",body:[:])
        _ = try await fixture("/qa/metrics",method:"POST",body:["mode":"ok"])
        let app = nativeApp()
        let cpu = app.otherElements["metrics.cpu"]
        let loaded = expectation(for:NSPredicate(format:"value CONTAINS %@","38%"),evaluatedWith:cpu)
        await fulfillment(of:[loaded],timeout:15)
        _ = try await fixture("/qa/metrics",method:"POST",body:["mode":"error"])
        let unavailable = expectation(for:NSPredicate(format:"value CONTAINS %@","读取失败"),evaluatedWith:cpu)
        await fulfillment(of:[unavailable],timeout:15)
        XCTAssertTrue((cpu.value as? String)?.hasPrefix("—") == true)
        _ = try await fixture("/qa/metrics",method:"POST",body:["mode":"ok"])
        let recovered = expectation(for:NSPredicate(format:"value CONTAINS %@","38%"),evaluatedWith:cpu)
        await fulfillment(of:[recovered],timeout:15)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS[c] %@","cancelled")).firstMatch.exists)
        save(app,name:"Build9-07-ResourcesRecovered")
    }

    @MainActor func testDashboardResourcesAndPrimaryInstances() async throws {
        _ = try await fixture("/qa/metrics", method: "POST", body: ["mode":"ok"])
        let app = nativeApp()
        let cpu = app.otherElements["metrics.cpu"]
        XCTAssertTrue(cpu.waitForExistence(timeout: 15))
        let loaded = expectation(for: NSPredicate(format: "value CONTAINS %@", "38%"), evaluatedWith: cpu)
        await fulfillment(of: [loaded], timeout: 15)
        XCTAssertTrue((app.otherElements["metrics.memory"].value as? String)?.contains("16.0 GB / 32.0 GB") == true)
        XCTAssertTrue((app.otherElements["metrics.disk"].value as? String)?.contains("70%") == true)
        save(app, name: "Build7-01-DashboardResources")
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForOrientation(app, landscape: true)
        XCTAssertTrue(cpu.exists)
        save(app, name: "Build7-06-DashboardLandscape")
        XCUIDevice.shared.orientation = .portrait
        waitForOrientation(app, landscape: false)
        _ = try await fixture("/qa/metrics", method: "POST", body: ["mode":"error"])
        let unavailable = expectation(for: NSPredicate(format: "value CONTAINS %@", "读取失败"), evaluatedWith: cpu)
        await fulfillment(of: [unavailable], timeout: 15)
        XCTAssertTrue((cpu.value as? String)?.hasPrefix("—") == true)
        save(app, name: "Build7-02-MetricsUnavailable")
        _ = try await fixture("/qa/metrics", method: "POST", body: ["mode":"ok"])
        let recovered = expectation(for: NSPredicate(format: "value CONTAINS %@", "38%"), evaluatedWith: cpu)
        await fulfillment(of: [recovered], timeout: 15)
        app.buttons["tab.servers"].tap()
        XCTAssertTrue(app.buttons["asset.ns-demo-eu.example"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["assets.filter.vps"].exists)
        XCTAssertFalse(app.buttons["plan.24ks-le-b"].exists)
        save(app, name: "Build7-03-PrimaryInstances")
        app.buttons["assets.filter.vps"].tap()
        XCTAssertTrue(app.buttons["asset.vps-demo-eu.example"].waitForExistence(timeout: 10))
        app.buttons["assets.filter.all"].tap()
        app.buttons["asset.ns-demo-eu.example"].tap()
        XCTAssertTrue(app.segmentedControls["detail.tabs"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        app.buttons["tab.more"].tap()
        XCTAssertTrue(app.buttons["more.servers"].exists)
        save(app, name: "Build7-04-MoreCatalog")
        // Let an in-flight dashboard request settle before counting hidden-tab traffic.
        let settled = expectation(description: "Leave dashboard")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { settled.fulfill() }
        await fulfillment(of: [settled], timeout: 5)
        let requests = try await fixture("/qa/metrics")["requests"] as? Int
        let hidden = expectation(description: "No dashboard polling while hidden")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { hidden.fulfill() }
        await fulfillment(of: [hidden], timeout: 5)
        let after = try await fixture("/qa/metrics")["requests"] as? Int
        XCTAssertEqual(after, requests)
        app.buttons["more.servers"].tap()
        XCTAssertTrue(app.buttons["plan.24ks-le-b"].waitForExistence(timeout: 20))
        save(app, name: "Build7-05-PreservedCatalog")
    }

    func testDashboardResourcesDarkAppearance() throws {
        let app = nativeApp(dark: true)
        let cpu = app.otherElements["metrics.cpu"]
        XCTAssertTrue(cpu.waitForExistence(timeout: 15))
        let loaded = expectation(for: NSPredicate(format: "value CONTAINS %@", "38%"), evaluatedWith: cpu)
        wait(for: [loaded], timeout: 15)
        save(app, name: "Build7-07-DashboardDark")
        app.buttons["tab.servers"].tap()
        XCTAssertTrue(app.buttons["asset.ns-demo-eu.example"].waitForExistence(timeout: 30))
        save(app, name: "Build7-08-InstancesDark")
    }
    private func save(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
