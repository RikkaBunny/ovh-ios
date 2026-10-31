import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/models.dart';
import 'common.dart';

class OfficialChatPage extends StatefulWidget {
  final Target target;
  const OfficialChatPage({super.key, required this.target});
  @override
  State<OfficialChatPage> createState() => _OfficialChatPageState();
}

class _OfficialChatPageState extends State<OfficialChatPage> {
  static const channel = MethodChannel('ovh_cp/official_chat');
  String product = 'dedicated';
  String? error;
  bool busy = false;
  int revision = 0;
  int? panelSession;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = PanelScope.of(context);
    final changed = panelSession != null && panelSession != store.session;
    panelSession = store.session;
    if (changed ||
        store.selectedAccount != widget.target.account ||
        store.connection == null) {
      revision++;
      if (Platform.isIOS) channel.invokeMethod<void>('close');
    }
  }

  @override
  void dispose() {
    revision++;
    if (Platform.isIOS) channel.invokeMethod<void>('close');
    super.dispose();
  }

  Future<void> open() async {
    final store = PanelScope.of(context), connection = store.connection;
    if (busy ||
        connection == null ||
        store.selectedAccount != widget.target.account) {
      return;
    }
    final session = store.session, request = ++revision;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      // Keep this one-time URL out of PanelStore, logs, history and result cards.
      final response = object(
        (await store.api.request(
          connection,
          '/ovh/support/chat/session',
          account: widget.target.account,
          method: 'POST',
          body: {'product': product},
        )).value,
      );
      if (!mounted ||
          request != revision ||
          session != store.session ||
          store.selectedAccount != widget.target.account) {
        return;
      }
      final url = Uri.tryParse(text(response['launchUrl']));
      if (response['accountId'] != widget.target.account ||
          url == null ||
          url.scheme != 'https' ||
          url.host != 'agent-chat.ovhcloud.com' ||
          url.path != '/sn_va_web_client_app_embed.do' ||
          url.userInfo.isNotEmpty ||
          url.port != 443) {
        throw const PanelException('官方客服返回的账户或地址不符');
      }
      if (Platform.isIOS) {
        await channel.invokeMethod<void>('open', {'url': url.toString()});
      } else {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (failure) {
      if (mounted &&
          request == revision &&
          session == store.session &&
          store.selectedAccount == widget.target.account) {
        setState(
          () => error = failure is PlatformException
              ? '无法打开官方客服：iOS 客服窗口未能显示，请返回后重试。'
              : '无法打开官方客服，请检查 GET /me、POST /auth/token 权限及后端版本。',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageLayout(
    '官方在线客服',
    account: false,
    child: PageList(
      children: [
        Text(widget.target.name),
        const Notice('官方聊天目前使用英语。接通情况取决于账户地区与支持等级，请在官方窗口核对客户身份。点击后才会申请一次性认证。'),
        DropdownButtonFormField<String>(
          initialValue: product,
          items: const [
            DropdownMenuItem(value: 'dedicated', child: Text('独立服务器')),
            DropdownMenuItem(value: 'vps', child: Text('VPS')),
          ],
          onChanged: busy ? null : (v) => setState(() => product = v!),
        ),
        if (error != null) Notice(error!),
        FilledButton(
          onPressed: busy ? null : open,
          child: Text(busy ? '正在准备…' : '打开 OVH 官方客服'),
        ),
      ],
    ),
  );
}
