import Flutter
import UIKit
import Security
import SafariServices

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var officialChat: SFSafariViewController?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    FlutterMethodChannel(name: "ovh_cp/official_chat", binaryMessenger: engineBridge.applicationRegistrar.messenger())
      .setMethodCallHandler { [weak self] call, result in
        guard let self else { result(nil); return }
        if call.method == "close" {
          let view = self.officialChat
          self.officialChat = nil
          if view?.presentingViewController != nil {
            view?.dismiss(animated: true) { result(nil) }
          } else {
            result(nil)
          }
          return
        }
        guard call.method == "open", let args = call.arguments as? [String: Any],
              let value = args["url"] as? String, let url = URL(string: value),
              url.scheme == "https", url.host == "agent-chat.ovhcloud.com",
              url.path == "/sn_va_web_client_app_embed.do", url.user == nil,
              url.port == nil || url.port == 443 else {
          result(FlutterError(code: "chat_url", message: "Invalid official chat destination", details: nil)); return
        }
        let sceneWindows = UIApplication.shared.connectedScenes
          .compactMap { $0 as? UIWindowScene }
          .filter { $0.activationState == .foregroundActive }
          .flatMap { $0.windows }
        let window = sceneWindows.first(where: { $0.isKeyWindow })
          ?? sceneWindows.first(where: { !$0.isHidden && $0.windowLevel == .normal })
          ?? self.window
        guard var presenter = window?.rootViewController else {
          result(FlutterError(code: "chat_window", message: "No active window", details: nil)); return
        }
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
          presenter = presented
        }
        guard presenter.viewIfLoaded?.window != nil, !presenter.isBeingDismissed else {
          result(FlutterError(code: "chat_window", message: "Window is not ready", details: nil)); return
        }
        let view = SFSafariViewController(url: url)
        self.officialChat = view
        presenter.present(view, animated: true) { result(nil) }
      }
    FlutterMethodChannel(name: "ovh_cp/system_symbol", binaryMessenger: engineBridge.applicationRegistrar.messenger())
      .setMethodCallHandler { call, result in
        guard call.method == "render", let args = call.arguments as? [String: Any],
              let name = args["name"] as? String, let size = args["size"] as? Double,
              size.isFinite, size > 0, size <= 128 else { result(FlutterMethodNotImplemented); return }
        let weight: UIImage.SymbolWeight = (args["weight"] as? Int ?? 400) >= 600 ? .semibold : .regular
        guard let image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: weight))?.withTintColor(.black, renderingMode: .alwaysOriginal) else { result(nil); return }
        guard let data = image.pngData() else { result(nil); return }
        result(["data": FlutterStandardTypedData(bytes: data),
                "width": image.size.width, "height": image.size.height])
      }
    FlutterMethodChannel(
      name: "ovh_cp/legacy_connection",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { call, result in
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.hejingcheng.ovhpocket.connection",
        kSecAttrAccount as String: "panel"
      ]
      switch call.method {
      case "read":
        var readQuery = query
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &item)
        if status == errSecItemNotFound { result(nil); return }
        guard status == errSecSuccess else {
          result(FlutterError(code: "legacy_keychain", message: "无法读取原版连接信息", details: nil))
          return
        }
        guard let data = item as? Data,
              let connection = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
          result(FlutterError(code: "legacy_format", message: "原版连接信息格式无效", details: nil))
          return
        }
        result([
          "address": connection["address"] ?? "",
          "secret": connection["key"] ?? "",
          "deviceToken": connection["authentication"] as? String == "deviceToken",
          "deviceId": connection["deviceID"] ?? NSNull(),
          "account": UserDefaults.standard.string(forKey: "selectedAccountID") ?? "",
          "appearance": UserDefaults.standard.string(forKey: "nativeAppearance") ?? "system"
        ])
      case "clear":
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
          UserDefaults.standard.removeObject(forKey: "selectedAccountID")
          result(nil)
        } else {
          result(FlutterError(code: "legacy_keychain", message: "无法清除原版连接信息", details: nil))
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
}
