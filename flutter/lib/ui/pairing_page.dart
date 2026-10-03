import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/models.dart';
import 'common.dart';

class PairingPage extends StatefulWidget {
  const PairingPage({super.key});
  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final address = TextEditingController(),
      code = TextEditingController(),
      deviceName = TextEditingController(text: '手机 · OVH Flutter');
  bool legacy = false;
  String? error;
  @override
  void dispose() {
    address.dispose();
    code.dispose();
    deviceName.dispose();
    super.dispose();
  }

  void accept(String payload) {
    try {
      final input = PairingInput.parse(payload);
      setState(() {
        address.text = input.address;
        code.text = input.code;
        legacy = false;
        error = null;
      });
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  Future<void> photo() async {
    final scanner = MobileScannerController(
      autoStart: false,
      formats: const [BarcodeFormat.qrCode],
    );
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null) return;
      final result = await scanner.analyzeImage(image.path);
      final payload = result?.barcodes
          .map((b) => b.rawValue)
          .whereType<String>()
          .firstOrNull;
      if (payload == null) throw const PanelException('图片中没有识别到配对二维码');
      if (mounted) accept(payload);
    } catch (e) {
      if (mounted) setState(() => error = '识别失败：$e');
    } finally {
      await scanner.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = PanelScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: PageList(
          children: [
            const SizedBox(height: 38),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset('assets/ovh.png', width: 86, height: 86),
              ),
            ),
            const Text(
              '连接 OVH 控制台',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
            const Text(
              '扫描网页「API 设置 → App 配对」的二维码，\n账户、实例与任务将使用同一份后端数据。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, height: 1.6),
            ),
            PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('pairing.address'),
                    controller: address,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '面板地址',
                      hintText: 'https://你的面板域名',
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    key: const Key('pairing.code'),
                    controller: code,
                    obscureText: legacy,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: legacy ? '访问密钥' : '8 位配对码',
                    ),
                  ),
                  if (!legacy) ...[
                    const SizedBox(height: 18),
                    TextField(
                      controller: deviceName,
                      decoration: const InputDecoration(labelText: '设备名称'),
                    ),
                  ],
                  const SizedBox(height: 22),
                  if (error ?? store.connectionError
                      case final String message) ...[
                    Notice(message),
                    const SizedBox(height: 16),
                  ],
                  FilledButton.icon(
                    key: const Key('pairing.connect'),
                    onPressed: store.connecting
                        ? null
                        : () async {
                            if (!await confirmAction(
                              context,
                              '连接此控制台',
                              address.text.trim(),
                            )) {
                              return;
                            }
                            await store.connect(
                              address.text,
                              code.text,
                              pair: !legacy,
                              deviceName: deviceName.text,
                            );
                          },
                    icon: store.connecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link),
                    label: Text(store.connecting ? '连接中…' : '连接控制台'),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final value = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(builder: (_) => const ScanPage()),
                          );
                          if (value != null && mounted) accept(value);
                        },
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('扫码'),
                      ),
                      OutlinedButton.icon(
                        onPressed: photo,
                        icon: const Icon(Icons.photo_outlined),
                        label: const Text('识别图片'),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          final value = await Clipboard.getData('text/plain');
                          if (mounted) accept(value?.text ?? '');
                        },
                        child: const Text('粘贴配对链接'),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      legacy = !legacy;
                      code.clear();
                    }),
                    child: Text(legacy ? '使用配对码连接' : '使用旧访问密钥'),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () =>
                  openHttps('https://ovh-review.hejingcheng.com/privacy'),
              child: const Text('隐私政策'),
            ),
          ],
        ),
      ),
    );
  }
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool detected = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('扫描配对二维码')),
    body: MobileScanner(
      controller: controller,
      onDetect: (capture) {
        final payload = capture.barcodes
            .map((b) => b.rawValue)
            .whereType<String>()
            .firstOrNull;
        if (payload != null && !detected) {
          detected = true;
          Navigator.pop(context, payload);
        }
      },
      errorBuilder: (context, error) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '相机不可用或未授权。可返回后识别二维码图片，或手动填写配对码。',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
