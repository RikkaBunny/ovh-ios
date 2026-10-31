import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ovh_flutter/core/api.dart';
import 'package:ovh_flutter/core/models.dart';
import 'package:ovh_flutter/core/store.dart';
import 'package:ovh_flutter/ui/common.dart';
import 'package:ovh_flutter/ui/official_chat_page.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ovh_cp/official_chat');
  testWidgets('Official chat opens and closes in the active iOS scene', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('OVH CP window test'))),
    );
    await tester.pumpAndSettle();
    await expectLater(
      channel.invokeMethod<void>('open', {'url': 'https://example.invalid/'}),
      throwsA(isA<PlatformException>()),
    );
    // No session token, credentials or backend authentication is used by this window test.
    try {
      await channel.invokeMethod<void>('open', {
        'url': 'https://agent-chat.ovhcloud.com/sn_va_web_client_app_embed.do',
      });
      debugPrint('OVH_CHAT_SCENE_WINDOW_OPENED');
    } finally {
      await channel.invokeMethod<void>('close');
    }
    await tester.pumpAndSettle();
    await binding.takeScreenshot('ChatWindowClosed');
  });
  testWidgets(
    'Native presentation failures are not reported as API permission failures',
    (tester) async {
      final catalog = Catalog(
        object(
          jsonDecode(await rootBundle.loadString('assets/NativeCatalog.json')),
        ),
      );
      final store = PanelStore(
        catalog,
        api: PanelApi(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'accountId': 'EU',
                'launchUrl':
                    'https://agent-chat.ovhcloud.com/sn_va_web_client_app_embed.do?sysparm_session_id=synthetic',
              }),
              200,
            ),
          ),
        ),
      );
      store.connection = Connection.validated(
        'https://example.invalid',
        'synthetic',
      );
      store.selectedAccount = 'EU';
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'open') {
          throw PlatformException(
            code: 'chat_window',
            message: 'Window is not ready',
          );
        }
        return null;
      });
      try {
        await tester.pumpWidget(
          PanelScope(
            store: store,
            child: MaterialApp(
              theme: panelTheme(Brightness.light),
              home: const OfficialChatPage(target: Target('EU', 'EU')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '打开 OVH 官方客服'));
        await tester.pumpAndSettle();
        expect(find.textContaining('iOS 客服窗口未能显示'), findsOneWidget);
        expect(find.textContaining('GET /me'), findsNothing);
        await binding.takeScreenshot('ChatWindowError');
        await tester.pumpWidget(const SizedBox());
      } finally {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
        store.dispose();
      }
    },
  );
}
