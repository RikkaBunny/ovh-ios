import SwiftUI
import WebKit

enum NativeActionRelations {
    static func actions(for read: NativeOperation, record: JSONValue, context: NativeContext) -> [(NativeOperation, NativeContext, [String: JSONValue])] {
        let aliases = ["task_id":"taskId","boot_id":"bootId","intervention_id":"id","ip_block":"ipBlock","domain":"domain","vrack":"name","option":"option","ip":"ip","id":"id"]
        let candidates = NativeCatalog.shared.operations.filter { op in
            guard op.id != read.id, op.scope == read.scope else { return false }
            if op.path == read.path { return !op.isRead }
            if op.path.hasPrefix(read.path + "/:") { return true }
            if read.path.hasSuffix("/templates") { return op.path.hasSuffix("/install") || op.path.hasSuffix("/reinstall") }
            return false
        }
        return candidates.compactMap { op in
            var target = context, seed = record.object
            for field in op.fields where field.location == "path" {
                let value = record[field.key] != .null ? record[field.key] : record[aliases[field.key] ?? ""] != .null ? record[aliases[field.key] ?? ""] : record.text.map(JSONValue.string) ?? .null
                if target.bindings[field.key] == nil { guard value != .null else { return nil }; target.bindings[field.key] = value }
            }
            if read.path.hasSuffix("/templates") {
                if read.scope == "vps" { seed["templateId"] = record["id"] }
                else { seed["templateName"] = record["templateName"] }
            }
            return (op,target,seed)
        }
    }
}

struct NativeResourceResults: View {
    let value: JSONValue
    let operation: NativeOperation
    let context: NativeContext
    private let collectionKeys = ["tasks","domains","ips","interventions","plannedInterventions","bootModes","boots","templates","accesses","options","vracks","pricings","devices","requests","contactChangeRequests","bills","refunds","emails","virtualMacs","interfaces","splaList","items"]
    private var collection: [JSONValue]? {
        if case .array = value { return value.array }
        return collectionKeys.compactMap { key -> [JSONValue]? in if case .array = value[key] { return value[key].array }; return nil }.first
    }
    private var consoleURL: URL? {
        for text in [value["url"].text,value["console"]["url"].text,value["console"]["value"].text,value["console"]["access"].text,value["consoleUrl"].text] {
            if let text, let url = URL(string: text), url.scheme == "https", url.host != nil { return url }
        }
        return nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if value["partial"].bool == true || (value["failedCount"].number ?? 0) > 0 { ErrorCard(message: "部分明细未能读取（\(Int(value["failedCount"].number ?? 0)) 项），请刷新重试。") }
            if operation.path.hasSuffix("/console"), let url = consoleURL {
                NavigationLink { NativeRemoteConsole(url: url, title: context.service ?? "远程控制台") } label: { Label("进入远程控制台", systemImage: "display").frame(maxWidth: .infinity) }.buttonStyle(CapsuleButtonStyle(solid: true))
            }
            if let rows = collection {
                if rows.isEmpty { NativeEmptyView(title: "暂无记录") }
                ForEach(Array(rows.enumerated()), id: \.offset) { row in
                    VStack(alignment: .leading, spacing: 12) {
                        NativeDataView(value: row.element)
                        ForEach(NativeActionRelations.actions(for: operation, record: row.element, context: context), id: \.0.id) { op, target, seed in NativeOperationLink(operation: op, context: target, seed: seed) }
                    }.padding(14).panel()
                }
            } else { NativeDataView(value: value).padding(16).panel() }
        }
    }
}

/// WebKit is limited to OVH's actual remote display protocol, never business pages.
struct NativeRemoteConsole: View {
    let url: URL
    let title: String
    @State private var error: String?
    var body: some View {
        VStack { if let error { ErrorCard(message: error).padding(14) }; RemoteDisplay(url: url, error: $error) }.page(title, back: true, showAccount: false)
    }
}

struct RemoteDisplay: UIViewRepresentable {
    let url: URL
    @Binding var error: String?
    func makeCoordinator() -> Coordinator { Coordinator(error: $error, origin: url) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config); view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url)); return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKNavigationDelegate {
        let error: Binding<String?>
        let origin: URL
        init(error: Binding<String?>, origin: URL) { self.error = error; self.origin = origin }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { self.error.wrappedValue = error.localizedDescription }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, url.scheme == "https" || url.scheme == "about", url.scheme == "about" || url.host == origin.host else { decisionHandler(.cancel); return }
            decisionHandler(.allow)
        }
    }
}

struct NativeOperationGroups: View {
    let operations: [NativeOperation]
    let context: NativeContext
    private var groups: [String] { Array(Set(operations.map { group($0) })).sorted() }
    var body: some View {
        VStack(spacing: 14) {
            ForEach(groups, id: \.self) { title in
                VStack(spacing: 0) {
                    DisclosureGroup {
                        ForEach(operations.filter { group($0) == title }) { op in NativeOperationLink(operation: op, context: context); Divider().padding(.leading, 48) }
                    } label: { Text(title).font(.system(size: 14, weight: .semibold)).padding(.vertical, 4) }.padding(14).tint(Theme.primary)
                }.panel()
            }
        }
    }
    private func group(_ op: NativeOperation) -> String {
        let path = op.path.components(separatedBy: "/:service_name/").last ?? op.path
        if path.hasPrefix("backup-ftp") { return "FTP 备份" }
        if path.hasPrefix("backup-cloud") || path.hasPrefix("automated-backup") { return "云备份" }
        if path.hasPrefix("secondary-dns") || path.hasPrefix("reverse") { return "DNS" }
        if path.hasPrefix("ola/") || path.hasPrefix("virtual") || path.hasPrefix("vrack") { return "虚拟网络与 vRack" }
        if path.hasPrefix("serviceinfo") || path.hasPrefix("engagement") || path.contains("terminat") || path == "change-contact" { return "续费、合同与联系人" }
        if path.hasPrefix("mitigation") || path == "firewall" || path == "burst" { return "防护与带宽" }
        if path.hasPrefix("ip") || path.hasPrefix("orderable") || path == "network-specs" { return "IP 与网络规格" }
        if path.hasPrefix("license") || path == "spla" || path.hasPrefix("bios") { return "授权与 BIOS" }
        return "其他服务"
    }
}

struct NativeQueueBatchBar: View {
    @EnvironmentObject var store: AppStore
    let items: [JSONValue]
    let onComplete: () -> Void
    @State private var action = ""
    @State private var confirming = false
    @State private var busy = false
    @State private var error: String?
    @State private var done = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("已选择 \(items.count) 个任务").font(.system(size: 13,weight:.medium))
            HStack { ForEach(["暂停","恢复","删除"],id:\.self) { title in Button(title) { action = title; confirming = true }.buttonStyle(CapsuleButtonStyle()) } }.disabled(busy)
            if busy { ProgressView("已处理 \(done) / \(items.count)",value:Double(done),total:Double(items.count)) }
            if let error { ErrorCard(message:error) }
        }.padding(14).panel()
            .sheet(isPresented:$confirming) {
                NavigationStack {
                    ScrollView { VStack(alignment:.leading,spacing:16) {
                        Text("\(action) \(items.count) 个任务").font(.system(size:18,weight:.semibold))
                        ForEach(Array(items.enumerated()),id:\.offset) { row in Text(summary(row.element)).font(.system(size:12)) }
                        Button("确认" + action) { confirming = false; Task { await perform() } }.buttonStyle(CapsuleButtonStyle(solid:true))
                    }.padding(20) }.navigationTitle("批量操作").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { confirming = false } } }
                }.presentationDragIndicator(.visible)
            }
    }
    private func summary(_ item: JSONValue) -> String {
        let name = store.accounts.first { $0.id == item["accountId"].rawText }?.name ?? "账户不可用"
        return [name,item["planCode"].rawText,item["datacenter"].rawText.uppercased()].joined(separator:" · ")
    }
    private func perform() async {
        guard !busy, let connection = store.connection else { return }; busy = true; done = 0; error = nil
        defer { busy = false }
        var failures: [String] = []
        for item in items {
            let base = "/queue/" + APIClient.component(item["id"].rawText)
            do {
                _ = try await APIClient(connection:connection).value(base + (action == "删除" ? "" : "/status"),method:action == "删除" ? "DELETE" : "PUT",body:action == "删除" ? nil : .object(["status":.string(action == "暂停" ? "paused" : "running")]))
                done += 1
            } catch { failures.append(item["planCode"].rawText + "：" + error.localizedDescription) }
        }
        if failures.isEmpty { onComplete() } else { error = "已成功处理 \(done) 个任务。\n" + failures.joined(separator:"\n") }
    }
}
