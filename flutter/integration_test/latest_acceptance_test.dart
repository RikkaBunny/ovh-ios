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
import 'package:ovh_flutter/ui/managed_action_page.dart';
import 'package:ovh_flutter/ui/operation_page.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Native iPhone renewal, withdrawal, rescue and support layouts', (
    tester,
  ) async {
    final catalog = Catalog(
      object(
        jsonDecode(await rootBundle.loadString('assets/NativeCatalog.json')),
      ),
    );
    final store = PanelStore(
      catalog,
      api: PanelApi(
        client: MockClient((r) async {
          dynamic data = {};
          if (r.url.path.endsWith('/serviceinfo')) {
            data = {
              'serviceInfo': {
                'renewalType': true,
                'renewalPeriod': 1,
                'renewalModes': ['automatic', 'manual'],
              },
            };
          }
          if (r.url.path.endsWith('/rescue')) {
            data = {
              'currentBoot': 1,
              'rescueConfigured': false,
              'boots': [
                {'bootId': 2, 'description': 'rescue-customer'},
              ],
            };
          }
          if (r.url.path.endsWith('/retraction')) {
            data = {
              'eligible': true,
              'orderId': 123456,
              'orderDate': '2026-10-30T10:00:00Z',
              'retractionDate': '2099-01-01T00:00:00Z',
            };
          }
          if (r.url.path.endsWith('/options')) {
            data = {
              'accountId': 'demo-us',
              'categories': ['assistance', 'billing', 'incident'],
              'products': ['dedicated', 'vps'],
              'subcategories': ['other'],
            };
          }
          if (r.url.path.endsWith('/services')) data = ['ns-demo.example'];
          {
            return http.Response(jsonEncode(data), 200);
          }
        }),
      ),
    );
    store.connection = Connection.validated(
      'https://example.invalid',
      'synthetic',
    );
    store.selectedAccount = 'demo-us';
    final target = const Target(
      'demo-us',
      '美区演示账户',
      service: 'ns-demo.example',
    );
    Future<void> show(Widget child) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        PanelScope(
          store: store,
          child: MaterialApp(theme: panelTheme(Brightness.light), home: child),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await show(
      ManagedActionPage(
        operation: catalog.op(
          'PUT',
          '/server-control/:service_name/serviceinfo/renewal',
        ),
        target: target,
      ),
    );
    expect(find.text('续费模式'), findsOneWidget);
    await binding.takeScreenshot('01-Renewal');
    await show(
      ManagedActionPage(
        operation: catalog.op(
          'POST',
          '/server-control/:service_name/retraction',
        ),
        target: target,
      ),
    );
    expect(find.textContaining('整张订单'), findsWidgets);
    await binding.takeScreenshot('02-Withdrawal');
    await show(
      ManagedActionPage(
        operation: catalog.op('POST', '/server-control/:service_name/rescue'),
        target: target,
      ),
    );
    expect(find.byKey(const Key('rescue.email')), findsOneWidget);
    await binding.takeScreenshot('03-Rescue');
    await show(
      OperationPage(
        operation: catalog.op('POST', '/ovh/support/tickets'),
        target: const Target('demo-us', '美区演示账户'),
      ),
    );
    expect(find.byKey(const Key('input.subject')), findsOneWidget);
    await binding.takeScreenshot('04-Support');
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
