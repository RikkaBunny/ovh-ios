import Foundation
import CoreImage

/// Contract from gokele/ovh: /api/app/pair#CODE and POST {code, deviceName}.
struct PairingInput: Equatable {
    let address: String
    let code: String

    static func normalizeCode(_ input: String) throws -> String {
        let code = input.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        let alphabet = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        guard code.count == 8, code.allSatisfy({ alphabet.contains($0) }) else {
            throw PanelError.message("请输入网页生成的 8 位配对码")
        }
        return code
    }

    static func fromQRCode(_ content: String) throws -> PairingInput {
        guard var parts = URLComponents(string: content.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.path == "/api/app/pair", parts.query == nil, let fragment = parts.fragment,
              parts.user == nil, parts.password == nil else {
            throw PanelError.message("这不是 OVH 面板的配对二维码，请在网页设置中重新生成")
        }
        // Upstream emits http when TLS terminates at a reverse proxy. Upgrade it;
        // the actual exchange always uses validated HTTPS, including custom ports.
        if parts.scheme?.lowercased() == "http" { parts.scheme = "https" }
        parts.path = ""; parts.fragment = nil
        let origin = try Connection.validated(address: parts.string ?? "", key: "validation").address
        return PairingInput(address: origin, code: try normalizeCode(fragment))
    }
}

struct PairingResponse: Decodable {
    let success: Bool
    let token: String
    let deviceId: Int
    let serverVersion: String?
}

extension APIClient {
    static func pairingRequest(address: String, code: String, deviceName: String) throws -> URLRequest {
        let origin = try Connection.validated(address: address, key: "validation").url
        let cleanCode = try PairingInput.normalizeCode(code)
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 60 else { throw PanelError.message("请填写设备名称，最长 60 字节（约 20 个汉字）") }
        var request = URLRequest(url: origin.appendingPathComponent("api/app/pair"), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": cleanCode, "deviceName": name])
        return request
    }

    static func pair(address: String, code: String, deviceName: String) async throws -> Connection {
        let origin = try Connection.validated(address: address, key: "validation").url
        let request = try pairingRequest(address: address, code: code, deviceName: deviceName)
        let result: PairingResponse = try await send(request, origin: origin, pairing: true)
        guard result.success, !result.token.isEmpty, result.deviceId > 0 else { throw PanelError.message("配对响应不完整，请重新生成配对码") }
        return try Connection.validated(address: address, key: result.token, authentication: .deviceToken, deviceID: result.deviceId)
    }
}

enum PairingQRCodeReader {
    static func read(_ data: Data) throws -> String {
        guard data.count <= 25_000_000, let image = CIImage(data: data, options: [.applyOrientationProperty: true]),
              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else {
            throw PanelError.message("图片无法读取，请使用清晰的二维码图片")
        }
        let codes = detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        guard codes.count == 1, let code = codes.first else {
            throw PanelError.message(codes.isEmpty ? "图片中没有识别到二维码" : "图片包含多个二维码，请选择只包含配对码的图片")
        }
        return code
    }
}
