import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/models.dart';
import 'common.dart';

class PairingPage extends StatefulWidget {
  final bool canDismiss;
  const PairingPage({super.key, this.canDismiss = false});
  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final address = TextEditingController(),
      code = TextEditingController(),
      deviceName = TextEditingController(text: '手机 · OVH CP');
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

  Future<void> connect() async {
    final store = PanelScope.of(context);
    if (!await confirmAction(context, '连接此控制台', address.text.trim())) return;
    await store.connect(
      address.text,
      code.text,
      pair: !legacy,
      deviceName: deviceName.text,
    );
    if (mounted && store.connection != null && widget.canDismiss) {
      Navigator.pop(context);
    }
  }

  Future<void> scan() async {
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
    if (value != null && mounted) accept(value);
  }

  Future<void> paste() async {
    final value = await Clipboard.getData('text/plain');
    if (mounted) accept(value?.text ?? '');
  }

  @override
  Widget build(BuildContext c) {
    final store = PanelScope.of(c);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (widget.canDismiss)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '设备配对',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: store.connecting
                          ? null
                          : () => Navigator.pop(c),
                      child: const Text('完成'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: PageList(
                maxWidth: 560,
                spacing: 20,
                padding: const EdgeInsets.all(22),
                storageKey: 'pairing',
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: widget.canDismiss ? 10 : 28),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/ovh.png',
                          width: 58,
                          height: 58,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '连接 OVH CP',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '在网页打开 API 设置 → App 配对，生成二维码。扫描后核对地址，再连接此设备。',
                        style: TextStyle(
                          fontSize: 13,
                          color: PanelDesign.muted(c),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                  if (!legacy)
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: store.connecting ? null : scan,
                            icon: const PanelIcon(
                              Icons.qr_code_scanner,
                              size: 16,
                            ),
                            label: const Text('扫描二维码'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: store.connecting ? null : photo,
                            icon: const PanelIcon(
                              Icons.photo_outlined,
                              size: 16,
                            ),
                            label: const Text('从图片识别'),
                          ),
                        ),
                      ],
                    ),
                  PanelCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '面板地址',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: PanelDesign.muted(c),
                          ),
                        ),
                        const SizedBox(height: 17),
                        TextField(
                          key: const Key('pairing.address'),
                          controller: address,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          style: const TextStyle(fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'https://你的面板域名',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 17),
                          child: Divider(),
                        ),
                        Text(
                          legacy ? '面板访问密钥' : '配对码 · 2 分钟有效',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: PanelDesign.muted(c),
                          ),
                        ),
                        const SizedBox(height: 17),
                        TextField(
                          key: const Key('pairing.code'),
                          controller: code,
                          obscureText: legacy,
                          autocorrect: false,
                          textCapitalization: TextCapitalization.characters,
                          style: TextStyle(
                            fontSize: legacy ? 14 : 18,
                            fontFamily: legacy ? null : 'Menlo',
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            hintText: legacy ? '输入面板的访问密钥' : '输入网页的 8 位配对码',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        if (!legacy) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 17),
                            child: Divider(),
                          ),
                          Text(
                            '设备名称',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: PanelDesign.muted(c),
                            ),
                          ),
                          const SizedBox(height: 17),
                          TextField(
                            key: const Key('pairing.deviceName'),
                            controller: deviceName,
                            style: const TextStyle(fontSize: 14),
                            decoration: const InputDecoration(
                              hintText: '在网页设备列表中显示',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (error ?? store.connectionError case final String message)
                    Notice(message),
                  FilledButton(
                    key: const Key('pairing.connect'),
                    onPressed: store.connecting ? null : connect,
                    child: Row(
                      children: [
                        if (store.connecting)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        Text(
                          store.connecting
                              ? '正在配对…'
                              : legacy
                              ? '连接面板'
                              : '配对并连接',
                        ),
                        const Spacer(),
                        const PanelIcon(Icons.arrow_forward, size: 15),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      PanelIcon(
                        Icons.lock_outline,
                        size: 14,
                        color: PanelDesign.muted(c),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '每台设备独立授权，令牌保存在本机系统安全存储',
                          style: PanelDesign.mutedText(c),
                        ),
                      ),
                    ],
                  ),
                  PanelCard(
                    padding: const EdgeInsets.all(14),
                    child: TextButton(
                      onPressed: paste,
                      child: const Row(
                        children: [
                          Expanded(child: Text('粘贴配对链接')),
                          PanelIcon(Icons.chevron_right, size: 11),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() {
                        legacy = !legacy;
                        code.clear();
                      }),
                      child: Text(legacy ? '使用配对码连接' : '使用面板访问密钥连接'),
                    ),
                  ),
                  Text(
                    '没有摄像头时，可识别二维码图片、粘贴配对链接，或手填配对码。设备授权可以在网页中单独撤销。',
                    style: PanelDesign.mutedText(c),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => openHttps(
                        'https://ovh-review.hejingcheng.com/privacy',
                      ),
                      child: const Text('隐私政策'),
                    ),
                  ),
                ],
              ),
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
