import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ovh_flutter/core/models.dart';
import 'package:ovh_flutter/core/managed_actions.dart';
import 'package:ovh_flutter/core/upstream_compat.dart';
import 'package:ovh_flutter/ui/managed_action_page.dart';
import 'package:ovh_flutter/ui/operation_page.dart';
import 'package:ovh_flutter/ui/official_chat_page.dart';
import 'core_test.dart' show loadCatalog, storeWith;
import 'upstream_compat_test.dart' show harness, clear;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'Latest contract preserves explicitly empty configuration selectors',
    () {
      final op = loadCatalog().op('PUT', '/monitor/subscriptions/:planCode');
      expect(
        op.resolve(
          {
            'options': ['ram-b'],
          },
          const Target('EU', 'EU').bind({'planCode': 'demo', 'optionsKey': ''}),
        ).query,
        {'optionsKey': ''},
      );
      expect(versionAtLeast('0.4.12', 0, 4, 5), true);
      expect(versionAtLeast('0.4.3', 0, 4, 5), false);
      expect(versionAtLeast('unknown', 0, 4, 5), false);
      expect(queueOrdered({'status': 'completed'}), true);
    },
  );
  test('Manual renewal uses service capabilities, never account geography', () {
    expect(
      renewalSupported({
        'renewalModes': ['automatic', 'manual'],
      }, 'manual'),
      true,
    );
    expect(
      renewalSupported({
        'renewalModes': ['automatic'],
      }, 'manual'),
      false,
    );
    expect(renewalSupported({}, 'manual'), null);
  });
  final target = const Target('EU', 'EU').bind({'order_id': 42});
  Json payment() => {
    'accountId': 'EU',
    'orderId': 42,
    'status': 'notPaid',
    'attempted': false,
    'amount': 12.5,
    'currency': 'EUR',
    'expirationDate': '2099-01-01T00:00:00Z',
    'methods': [
      {'id': 7, 'type': 'bankCard', 'label': 'Demo card'},
    ],
  };
  test('Payment pins account, order, amount and an allowed method', () {
    expect(checkedPayment(payment(), target, '7'), {
      'confirm': true,
      'amount': 12.5,
      'currency': 'EUR',
      'paymentMethodId': 7,
      'paymentType': 'bankCard',
    });
    for (final change in [
      {'accountId': 'US'},
      {'orderId': 43},
      {'attempted': true},
      {'status': 'paid'},
      {'amount': null},
      {'expirationDate': 'bad'},
    ]) {
      expect(
        () => checkedPayment({...payment(), ...change}, target, 7),
        throwsA(isA<PanelException>()),
      );
    }
    expect(
      () => checkedPayment(payment(), target, 8),
      throwsA(isA<PanelException>()),
    );
  });
  test(
    'Rescue requires a complete email instead of display names or partial addresses',
    () {
      expect(completeRescueEmail('a@example.com'), true);
      for (final s in [
        'a@',
        'abc',
        'Name <a@example.com>',
        'a b@example.com',
      ]) {
        expect(completeRescueEmail(s), false);
      }
    },
  );
  testWidgets(
    'Rescue waits for boot status and changing email clears confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <http.Request>[];
      final store = storeWith((r) async {
        requests.add(r);
        return http.Response(
          jsonEncode(r.method == 'GET' ? {'currentBoot': 1, 'boots': []} : {}),
          200,
        );
      });
      await tester.pumpWidget(
        harness(
          store,
          ManagedActionPage(
            operation: loadCatalog().op(
              'POST',
              '/server-control/:service_name/rescue',
            ),
            target: const Target('EU', 'EU', service: 'ns-demo'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      await tester.enterText(
        find.byKey(const Key('rescue.email')),
        'a@example.com',
      );
      await tester.ensureVisible(find.byKey(const Key('managed.confirm')));
      await tester.tap(find.byKey(const Key('managed.confirm')));
      await tester.pump();
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('managed.confirm')))
            .value,
        true,
      );
      await tester.ensureVisible(find.byKey(const Key('rescue.email')));
      await tester.enterText(
        find.byKey(const Key('rescue.email')),
        'b@example.com',
      );
      await tester.pump();
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('managed.confirm')))
            .value,
        false,
      );
      expect(tester.takeException(), isNull);
      await clear(tester, store);
    },
  );
  testWidgets('Payment is only read until explicit method and confirmation', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final store = storeWith((r) async {
      requests.add(r);
      return http.Response(jsonEncode(payment()), 200);
    });
    await tester.pumpWidget(
      harness(
        store,
        ManagedActionPage(
          operation: loadCatalog().op(
            'POST',
            '/ovh/account/orders/:order_id/pay',
          ),
          target: target,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests.single.url.path, '/api/ovh/account/orders/42/payment');
    expect(requests.single.url.queryParameters['account'], 'EU');
    expect(requests.single.method, 'GET');
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('managed.submit')))
          .onPressed,
      isNull,
    );
    await clear(tester, store);
  });
  testWidgets('Withdrawal never lets users type a different order', (
    tester,
  ) async {
    final store = storeWith(
      (_) async => http.Response(
        jsonEncode({
          'eligible': true,
          'orderId': 42,
          'retractionDate': '2099-01-01T00:00:00Z',
        }),
        200,
      ),
    );
    await tester.pumpWidget(
      harness(
        store,
        ManagedActionPage(
          operation: loadCatalog().op(
            'POST',
            '/server-control/:service_name/retraction',
          ),
          target: const Target('EU', 'EU', service: 'ns-demo'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('整张订单'), findsWidgets);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('managed.submit')))
          .onPressed,
      isNull,
    );
    await clear(tester, store);
  });
  test(
    'Completed queue state blocks stale resume requests before HTTP',
    () async {
      var sent = 0;
      final store = storeWith((_) async {
        sent++;
        return http.Response('{}', 200);
      });
      store.state('/queue').value = [
        {'id': 'done', 'status': 'completed'},
      ];
      await expectLater(
        store.execute(
          loadCatalog().op('PUT', '/queue/:id/status'),
          const Target('EU', 'EU').bind({'id': 'done'}),
          {'status': 'running'},
        ),
        throwsA(isA<PanelException>()),
      );
      expect(sent, 0);
      store.dispose();
    },
  );
  testWidgets(
    'Queue edit sends a full snapshot even when fields are unchanged',
    (tester) async {
      http.Request? saved;
      final store = storeWith((r) async {
        if (r.method == 'PUT') saved = r;
        return http.Response('{}', 200);
      });
      await tester.pumpWidget(
        harness(
          store,
          OperationPage(
            operation: loadCatalog().op('PUT', '/queue/:id'),
            target: const Target('EU', 'EU').bind({'id': 'q1'}),
            seed: const {
              'datacenter': 'gra',
              'retryInterval': 60,
              'options': ['ram-a'],
              'autoPay': false,
              'coupon': 'DEMO',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('operation.submit')));
      await tester.tap(find.byKey(const Key('operation.submit')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('operation.confirm')));
      await tester.tap(find.byKey(const Key('operation.confirm')));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(jsonDecode(saved!.body), {
        'datacenter': 'gra',
        'retryInterval': 60,
        'options': ['ram-a'],
        'autoPay': false,
        'coupon': 'DEMO',
      });
      await clear(tester, store);
    },
  );
  testWidgets('Withdrawal POST uses the displayed order and only fires once', (
    tester,
  ) async {
    final writes = <http.Request>[];
    final store = storeWith((r) async {
      if (r.method == 'POST') writes.add(r);
      return http.Response(
        jsonEncode({
          'eligible': true,
          'orderId': 42,
          'retractionDate': '2099-01-01T00:00:00Z',
        }),
        200,
      );
    });
    await tester.pumpWidget(
      harness(
        store,
        ManagedActionPage(
          operation: loadCatalog().op(
            'POST',
            '/server-control/:service_name/retraction',
          ),
          target: const Target('EU', 'EU', service: 'ns-demo'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('managed.confirm')));
    await tester.tap(find.byKey(const Key('managed.confirm')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('managed.submit')));
    await tester.tap(find.byKey(const Key('managed.submit')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('operation.confirm')));
    await tester.tap(find.byKey(const Key('operation.confirm')));
    await tester.pumpAndSettle();
    expect(writes.length, 1);
    expect(jsonDecode(writes.single.body), {
      'confirm': true,
      'orderId': 42,
      'reason': 'other',
    });
    expect(find.byKey(const Key('managed.submit')), findsNothing);
    await clear(tester, store);
  });
  testWidgets('Chat authentication is explicit and refuses a different account', (
    tester,
  ) async {
    var calls = 0;
    final store = storeWith((r) async {
      calls++;
      expect(r.url.queryParameters['account'], 'EU');
      return http.Response(
        jsonEncode({
          'accountId': 'US',
          'launchUrl':
              'https://agent-chat.ovhcloud.com/sn_va_web_client_app_embed.do?sysparm_session_id=synthetic',
        }),
        200,
      );
    });
    await tester.pumpWidget(
      harness(store, const OfficialChatPage(target: Target('EU', 'EU'))),
    );
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.widgetWithText(FilledButton, '打开 OVH 官方客服'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('无法打开官方客服'), findsOneWidget);
    await clear(tester, store);
  });
  testWidgets('Late chat authentication cannot open a previous account window', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final store = storeWith(
      (r) async => r.url.path.endsWith('/chat/session')
          ? pending.future
          : http.Response('{}', 200),
    );
    store.accounts = [
      Account({'id': 'EU', 'name': 'EU'}),
      Account({'id': 'US', 'name': 'US'}),
    ];
    await tester.pumpWidget(
      harness(store, const OfficialChatPage(target: Target('EU', 'EU'))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '打开 OVH 官方客服'));
    await tester.pump();
    await store.select('US');
    await tester.pump();
    pending.complete(
      http.Response(
        jsonEncode({
          'accountId': 'EU',
          'launchUrl':
              'https://agent-chat.ovhcloud.com/sn_va_web_client_app_embed.do?sysparm_session_id=synthetic',
        }),
        200,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('无法打开官方客服'), findsNothing);
    await clear(tester, store);
  });
}
