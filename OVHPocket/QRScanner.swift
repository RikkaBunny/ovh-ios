import SwiftUI
import VisionKit
import AVFoundation

struct QRScannerScreen: View {
    @Environment(\.dismiss) private var dismiss
    let onRead: (String) -> Void
    @State private var ready = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("扫描配对二维码").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(CapsuleButtonStyle()).accessibilityIdentifier("pairing.cancelScanner")
            }.padding(14).background(Theme.background)
            if ready {
                CameraQRScanner(onRead: onRead, onError: { error = $0; ready = false })
            } else if let error {
                ContentUnavailableView("摄像头不可用", systemImage: "qrcode.viewfinder", description: Text(error)).frame(maxHeight: .infinity)
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.background(Theme.background).foregroundStyle(Theme.primary)
            .task {
                #if targetEnvironment(simulator)
                error = "模拟器没有摄像头。返回后可从图片识别、粘贴配对链接，或输入 8 位配对码。"
                #else
                guard DataScannerViewController.isSupported else { error = "此设备不支持扫码，请返回并从图片识别二维码。"; return }
                let allowed = await AVCaptureDevice.requestAccess(for: .video)
                guard allowed else { error = "请在系统设置中允许摄像头访问，或返回后从图片识别二维码。"; return }
                guard DataScannerViewController.isAvailable else { error = "摄像头暂时不可用，请稍后重试。"; return }
                ready = true
                #endif
            }
    }
}

private struct CameraQRScanner: UIViewControllerRepresentable {
    let onRead: (String) -> Void
    let onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
            recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true,
            isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        do { try scanner.startScanning() }
        catch { Task { @MainActor in onError("扫码无法启动，请返回后从图片识别二维码。") } }
        return scanner
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) { context.coordinator.parent = self }
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning(); controller.delegate = nil
    }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: CameraQRScanner
        private var delivered = false
        init(parent: CameraQRScanner) { self.parent = parent }
        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) { read(allItems, scanner: scanner) }
        func dataScanner(_ scanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) { read(allItems, scanner: scanner) }
        func dataScanner(_ scanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            parent.onError("摄像头暂时不可用，请返回后重试或从图片识别。")
        }
        private func read(_ items: [RecognizedItem], scanner: DataScannerViewController) {
            guard !delivered else { return }
            for item in items {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    delivered = true; scanner.stopScanning(); parent.onRead(value); return
                }
            }
        }
    }
}
