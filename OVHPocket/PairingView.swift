import SwiftUI
import PhotosUI

struct PairingView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var canDismiss = false
    @State private var address = ""
    @State private var code = ""
    @State private var deviceName = UIDevice.current.model + " · OVH"
    @State private var link = ""
    @State private var localError: String?
    @State private var scanner = false
    @State private var legacy = false
    @State private var photo: PhotosPickerItem?
    @State private var readingPhoto = false

    var body: some View {
        VStack(spacing: 0) {
            if canDismiss {
                HStack {
                    Text("设备配对").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Button("完成") { dismiss() }.buttonStyle(CapsuleButtonStyle()).disabled(store.connecting)
                }.padding(14).background(Theme.background)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "qrcode").font(.system(size: 29)).foregroundStyle(Theme.onPrimary)
                            .frame(width: 58, height: 58).background(Theme.primary, in: RoundedRectangle(cornerRadius: 12))
                        Text("连接你的控制台").font(.system(size: 27, weight: .bold))
                        Text("在网页打开 API 设置 → App 配对，生成二维码。扫描后核对地址，再连接此设备。").font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(4)
                    }.padding(.top, canDismiss ? 10 : 28)
                    HStack(spacing: 10) {
                        Button { localError = nil; scanner = true } label: { Label("扫描二维码", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity) }
                            .buttonStyle(CapsuleButtonStyle(solid: true)).accessibilityIdentifier("pairing.scan")
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label(readingPhoto ? "识别中…" : "从图片识别", systemImage: "photo").frame(maxWidth: .infinity)
                        }.buttonStyle(CapsuleButtonStyle()).accessibilityIdentifier("pairing.photo")
                    }.disabled(store.connecting || readingPhoto)
                    VStack(alignment: .leading, spacing: 17) {
                        inputLabel("面板地址")
                        TextField("https://你的面板域名", text: $address).keyboardType(.URL).textContentType(.URL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("pairing.address")
                        Divider()
                        inputLabel("配对码 · 2 分钟有效")
                        TextField("输入网页的 8 位配对码", text: $code).keyboardType(.asciiCapable).textInputAutocapitalization(.characters)
                            .autocorrectionDisabled().font(.system(size: 18, weight: .medium, design: .monospaced))
                            .accessibilityIdentifier("pairing.code")
                        Divider()
                        inputLabel("设备名称")
                        TextField("在网页设备列表中显示", text: $deviceName).autocorrectionDisabled().accessibilityIdentifier("pairing.deviceName")
                    }.font(.system(size: 14)).padding(18).panel()
                    if let error = localError ?? store.error { ErrorCard(message: error).accessibilityIdentifier("pairing.error") }
                    Button {
                        localError = nil
                        Task {
                            if await store.pair(address: address, code: code, deviceName: deviceName) {
                                code = ""; link = ""
                                if canDismiss { dismiss() }
                            }
                        }
                    } label: {
                        HStack { if store.connecting { ProgressView().tint(Theme.onPrimary) }; Text(store.connecting ? "正在配对…" : "配对并连接"); Spacer(); Image(systemName: "arrow.right") }
                    }.buttonStyle(CapsuleButtonStyle(solid: true)).disabled(store.connecting || readingPhoto).accessibilityIdentifier("pairing.submit")
                    Label("每台设备独立授权，令牌保存在本机钥匙串", systemImage: "lock.shield").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("网页生成的二维码链接", text: $link).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("pairing.link")
                            Button("识别链接") { accept(link) }.buttonStyle(CapsuleButtonStyle()).accessibilityIdentifier("pairing.readLink")
                        }.padding(.top, 12)
                    } label: { Text("粘贴配对链接").accessibilityIdentifier("pairing.linkDisclosure") }
                        .font(.system(size: 13)).padding(14).panel()
                    Button("使用面板访问密钥连接") { store.error = nil; localError = nil; legacy = true }
                        .font(.system(size: 13)).buttonStyle(.plain).accessibilityIdentifier("pairing.legacy")
                    Text("没有摄像头时，可识别二维码图片、粘贴配对链接，或手填配对码。设备授权可以在网页中单独撤销。").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Link("隐私政策", destination: URL(string: "https://ovh-review.hejingcheng.com/privacy")!).font(.system(size: 12)).accessibilityIdentifier("pairing.privacy")
                }.padding(22).frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
        }.background(Theme.background).foregroundStyle(Theme.primary)
            .onAppear { if let connection = store.connection { address = connection.address } }
            .sheet(isPresented: $scanner) {
                QRScannerScreen(onRead: { content in scanner = false; accept(content) })
            }
            .sheet(isPresented: $legacy) {
                VStack(spacing: 0) {
                    HStack { Text("访问密钥连接").font(.system(size: 16, weight: .semibold)); Spacer(); Button("完成") { legacy = false }.buttonStyle(CapsuleButtonStyle()) }.padding(14)
                    LegacyConnectForm()
                }.background(Theme.background)
            }
            .onChange(of: photo) { _, selected in
                guard let selected else { return }
                readingPhoto = true; localError = nil
                Task {
                    defer { readingPhoto = false; photo = nil }
                    do {
                        guard let data = try await selected.loadTransferable(type: Data.self) else { throw PanelError.message("无法读取所选图片") }
                        let content = try await Task.detached { try PairingQRCodeReader.read(data) }.value
                        accept(content)
                    } catch { localError = error.localizedDescription }
                }
            }
    }

    private func inputLabel(_ title: String) -> some View { Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted) }
    private func accept(_ content: String) {
        do { let input = try PairingInput.fromQRCode(content); address = input.address; code = input.code; localError = nil; store.error = nil }
        catch { localError = error.localizedDescription }
    }
}
