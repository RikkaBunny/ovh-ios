import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ovh_flutter/core/models.dart';
import 'package:ovh_flutter/core/store.dart';
import 'package:ovh_flutter/core/upstream_compat.dart';
import 'package:ovh_flutter/ui/common.dart';
import 'package:ovh_flutter/ui/inventory.dart';
import 'package:ovh_flutter/ui/pages.dart';
import 'core_test.dart' show loadCatalog, storeWith;

const variants = <Json>[
  {
    'planCode': '26rise01',
    'server': 'RISE Future',
    'memory': 'ram-32',
    'storage': 'ssd-1',
    'datacenters': [
      {'datacenter': 'gra', 'availability': 'unavailable'},
    ],
  },
  {
    'planCode': '26rise01',
    'server': 'RISE Future',
    'memory': 'ram-64',
    'storage': 'ssd-2',
    'datacenters': [
      {'datacenter': 'bhs', 'availability': 'available'},
    ],
  },
];

void setupAccount(PanelStore store) {
  store.accounts = [
    Account({
      'id': 'EU',
      'name': 'EU Test',
      'endpoint': 'ovh-eu',
      'zone': 'FR',
    }),
  ];
  store.selectedAccount = 'EU';
}

Widget harness(PanelStore store, Widget page) => PanelScope(
  store: store,
  child: MaterialApp(theme: panelTheme(Brightness.light), home: page),
);
Future<void> clear(WidgetTester tester, PanelStore store) async {
  await tester.pumpWidget(const SizedBox());
  store.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'v0.4.12 exposes new native operations and required preorder identity',
    () {
      final catalog = loadCatalog();
      expect(catalog.commit, '707671a0b053f9e9da4044b17283d73006e502de');
      expect(catalog.op('GET', '/ovh/account/orders').title, 'OVH 官方订单');
      expect(
        catalog
            .op('POST', '/queue')
            .fields
            .firstWhere((f) => f.key == 'account_id')
            .required,
        true,
      );
      expect(
        catalog
            .op('POST', '/monitor/subscriptions/:planCode/pause')
            .fields
            .firstWhere((f) => f.key == 'paused')
            .required,
        true,
      );
      expect(
        catalog
            .op('POST', '/server-control/:service_name/install')
            .fields
            .firstWhere((f) => f.key == 'customizations')
            .kind,
        'object',
      );
    },
  );
  test(
    'Preorders merge only supported Eco stock candidates and remain searchable',
    () {
      final plans = mergeStockPlans(
        [
          {'planCode': '26sk01', 'name': 'Existing'},
        ],
        [
          ...variants,
          {'planCode': '26sk01'},
          {'planCode': '26adv01'},
          {'planCode': 'not-an-eco-plan'},
        ],
      );
      expect(plans.map((p) => p['planCode']), ['26sk01', '26rise01']);
      expect(planSearchText(plans.last), contains('预发布'));
      expect(planSearchText(plans.last), contains('prerelease'));
      expect(
        preorderConfigurationMatches(plans.last, ['ram-32', 'ssd-2']),
        false,
      );
      expect(
        preorderConfigurationMatches(plans.last, ['ram-64', 'ssd-2']),
        true,
      );
      expect(preorderConfigurationMatches(plans.last, []), true);
    },
  );
  test('Subscription identity preserves exact Go sort-and-join semantics', () {
    final options = ['b', 'a', 'a'];
    expect(subscriptionOptionsKey(options), 'a,a,b');
    expect(options, ['b', 'a', 'a']);
    final first = {
      'planCode': '26sk01',
      'options': ['ram-32'],
    };
    final next = {
      'planCode': '26sk01',
      'options': ['ram-64'],
    };
    final all = {'planCode': '26sk01', 'options': <String>[]};
    expect(subscriptionCanAddress(next, [first, next]), true);
    expect(subscriptionIsUnique(next, [first, next]), false);
    expect(subscriptionCanAddress(all, [first, all]), false);
    expect(subscriptionCanAddress(all, [all, first]), false);
    expect(subscriptionCanAddress(all, [all]), true);
    final op = loadCatalog().op('DELETE', '/monitor/subscriptions/:planCode');
    final request = op.resolve(
      {},
      const Target('EU', 'EU').bind({
        'planCode': '26sk01',
        'optionsKey': subscriptionOptionsKey(next['options']),
      }),
    );
    expect(request.query, {'optionsKey': 'ram-64'});
  });
  test(
    'OVH business 401 retains panel pairing and the real error message',
    () async {
      final store = storeWith(
        (_) async => http.Response(
          jsonEncode({
            'success': false,
            'error': 'OVH permission denied',
            'code': 'OVH_UPSTREAM_ERROR',
          }),
          401,
        ),
      );
      await store.load('/stats');
      expect(store.connection, isNotNull);
      expect(store.state('/stats').error, contains('OVH permission denied'));
      store.dispose();
    },
  );
  test('Explicit invalid device token revokes saved pairing', () async {
    final store = storeWith(
      (_) async => http.Response(
        jsonEncode({'code': 'INVALID_DEVICE_TOKEN', 'message': 'revoked'}),
        401,
      ),
    );
    await store.load('/stats');
    expect(store.connection, isNull);
    store.dispose();
  });
  test('Public inventory 401 does not invalidate panel credentials', () async {
    final store = storeWith(
      (_) async => http.Response(
        jsonEncode({'success': false, 'error': 'upstream unauthorized'}),
        401,
      ),
    );
    await store.load(
      '@stock/EU',
      fetch: (c) => store.api.stock(
        Account({'id': 'EU', 'endpoint': 'ovh-eu', 'zone': 'FR'}),
        c,
      ),
    );
    expect(store.connection, isNotNull);
    store.dispose();
  });

  test(
    'Template customizations preserve scalar types and reject missing required input',
    () {
      final questions = [
        {
          'name': 'sshKey',
          'required': true,
          'type': 'string',
          'description': 'SSH 公钥',
        },
        {'name': 'enableLacpBonding', 'type': 'boolean'},
        {'name': 'postInstallationScript', 'type': 'string'},
      ];
      expect(
        () => normalizedCustomizations(questions, {}),
        throwsA(isA<PanelException>()),
      );
      expect(
        normalizedCustomizations(questions, {
          'sshKey': 'ssh-ed25519 fixture',
          'enableLacpBonding': true,
          'irrelevant': 'ignored',
        }),
        {'sshKey': 'ssh-ed25519 fixture', 'enableLacpBonding': true},
      );
      expect(installationQuestionFields(questions).last['kind'], 'multiline');
      expect(
        () => normalizedCustomizations(questions, {
          'sshKey': 'fixture',
          'enableLacpBonding': 'true',
        }),
        throwsA(isA<PanelException>()),
      );
    },
  );
  testWidgets('Inventory search discovers prerelease stock plans', (
    tester,
  ) async {
    final store = storeWith(
      (r) async => http.Response(
        jsonEncode(
          r.url.path == '/api/servers'
              ? [
                  {'planCode': '26sk01', 'name': 'Existing'},
                ]
              : r.url.path.contains('availabilities')
              ? variants
              : {},
        ),
        200,
      ),
    );
    setupAccount(store);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness(store, const InventoryPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('inventory.search')), '预发布');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan.26rise01')), findsOneWidget);
    expect(find.byKey(const Key('plan.26sk01')), findsNothing);
    expect(tester.takeException(), isNull);
    await clear(tester, store);
  });
  testWidgets(
    'Preorder submits selected account and explicit non-paying task',
    (tester) async {
      Json? sent;
      final store = storeWith((r) async {
        if (r.url.path == '/api/queue' && r.method == 'POST') {
          sent = object(jsonDecode(r.body));
        }
        return http.Response(
          jsonEncode(r.url.path.endsWith('/list') ? [] : {}),
          200,
        );
      });
      setupAccount(store);
      final plan = mergeStockPlans([], variants).single;
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        harness(
          store,
          OrderPage(
            plan: plan,
            target: store.target,
            options: const ['ram-64', 'ssd-2'],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(CheckboxListTile, 'BHS'));
      await tester.tap(find.widgetWithText(CheckboxListTile, 'BHS'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('order.submit')));
      await tester.tap(find.byKey(const Key('order.submit')));
      await tester.pumpAndSettle();
      expect(find.text('确认创建预约抢购任务'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('operation.confirm')));
      await tester.tap(find.byKey(const Key('operation.confirm')));
      await tester.pumpAndSettle();
      expect(sent, containsPair('account_id', 'EU'));
      expect(sent, containsPair('preorder', true));
      expect(sent, containsPair('autoPay', false));
      expect(sent?['options'], ['ram-64', 'ssd-2']);
      expect(tester.takeException(), isNull);
      await clear(tester, store);
    },
  );
  testWidgets('Pause targets the chosen configuration of the same plan', (
    tester,
  ) async {
    Json? sent;
    final rows = <Json>[
      {
        'planCode': '26sk01',
        'serverName': 'KS',
        'options': ['ram-32'],
        'paused': false,
      },
      {
        'planCode': '26sk01',
        'serverName': 'KS',
        'options': ['ram-64'],
        'paused': false,
      },
    ];
    final store = storeWith((r) async {
      if (r.url.path.endsWith('/pause')) {
        sent = object(jsonDecode(r.body));
        rows[1]['paused'] = true;
      }
      final value = r.url.path == '/api/monitor/subscriptions'
          ? rows
          : r.url.path == '/api/monitor/status'
          ? {'running': true, 'check_interval': 60}
          : r.url.path.endsWith('/list')
          ? []
          : {};
      return http.Response(jsonEncode(value), 200);
    });
    setupAccount(store);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness(store, const MonitorPage()));
    await tester.pumpAndSettle();
    final second = find.byKey(const ValueKey('monitor.pause.26sk01|ram-64'));
    await tester.ensureVisible(second);
    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(sent, {'optionsKey': 'ram-64', 'paused': true});
    expect(rows.first['paused'], false);
    expect(find.text('恢复监控'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await clear(tester, store);
  });
  testWidgets(
    'Subscription details refresh pause state and reject a removed selection',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final original = <String, dynamic>{
        'planCode': '26sk01',
        'options': ['ram-64'],
        'paused': false,
      };
      var source = <Json>[original];
      final store = storeWith(
        (r) async => http.Response(jsonEncode(source), 200),
      );
      setupAccount(store);
      await store.load('/monitor/subscriptions');
      await tester.pumpWidget(harness(store, SubscriptionDetailPage(original)));
      await tester.pumpAndSettle();
      source = [
        {...original, 'paused': true},
      ];
      await store.load('/monitor/subscriptions');
      await tester.pumpAndSettle();
      final pause = find.byKey(const Key('native.PauseSubscription'));
      await tester.ensureVisible(pause);
      await tester.tap(pause);
      await tester.pumpAndSettle();
      expect(tester.widget<PanelSwitch>(find.byType(PanelSwitch)).value, true);
      await tester.tap(find.byKey(const Key('app.back')));
      await tester.pumpAndSettle();
      source = [];
      await store.load('/monitor/subscriptions');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('native.PauseSubscription')), findsNothing);
      expect(find.text('该订阅配置已变更或删除，请返回列表重新选择。'), findsOneWidget);
      await clear(tester, store);
    },
  );
}
