import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ovh_flutter/app.dart';
import 'package:ovh_flutter/core/api.dart';
import 'package:ovh_flutter/core/models.dart';
import 'package:ovh_flutter/core/store.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var androidSurfaceConverted = false;
  late PanelStore store;
  final control = PanelApi();
  final fixture = Connection.validated(
    'https://localhost:16443',
    'OVH-AppReview-2026',
  );
  Future<dynamic> qa(String path, [Json? body]) async => (await control.request(
    fixture,
    path,
    method: body == null ? 'GET' : 'POST',
    body: body,
  )).value;
  Future<void> waitFor(
    WidgetTester tester,
    bool Function() predicate, {
    int seconds = 15,
  }) async {
    for (var i = 0; i < seconds * 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (predicate()) return;
    }
    expect(
      predicate(),
      true,
      reason: 'Expected state did not arrive within $seconds seconds',
    );
  }

  Future<void> open(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (Platform.isAndroid && !androidSurfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      androidSurfaceConverted = true;
      await tester.pumpAndSettle();
    }
    await tester.pumpAndSettle();
    await binding.takeScreenshot(name);
  }

  Future<void> start(WidgetTester tester) async {
    await qa('/qa/refresh', {'mode': 'ok', 'delay': 0, 'marker': 0});
    await qa('/qa/inventory', {'mode': 'ok', 'delay': 0});
    await qa('/qa/metrics', {'mode': 'ok'});
    final catalog = Catalog(
      object(
        jsonDecode(await rootBundle.loadString('assets/NativeCatalog.json')),
      ),
    );
    store = PanelStore(catalog);
    await store.setAppearance('light');
    await store.connect(fixture.address, fixture.secret);
    await tester.pumpWidget(OVHApp(store: store, restore: false));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    store.dispose();
  }

  Future<void> dashboard(WidgetTester tester) async {
    await start(tester);
    expect(find.text('系统资源'), findsOneWidget);
    expect(find.byKey(const Key('resource.cpu')), findsOneWidget);
    final scroll = find.byType(Scrollable).first;
    await qa('/qa/refresh', {'mode': 'ok', 'delay': 1, 'marker': 17});
    await tester.drag(scroll, const Offset(0, 480));
    await tester.pump(const Duration(milliseconds: 150));
    await waitFor(
      tester,
      () => object(store.state('/stats').value)['totalServers'] == 17,
    );
    expect(store.state('/stats').error, isNull);
    expect(find.textContaining('cancelled'), findsNothing);
    await screenshot(tester, 'Flutter-01-Dashboard');
    await open(tester, find.byKey(const Key('tab.instances')));
    await waitFor(
      tester,
      () => store.assets.any((a) => a.name.contains('refresh-17')),
    );
    final oldNames = store.assets.map((a) => a.name).toList();
    await qa('/qa/refresh', {'mode': 'error', 'delay': .4, 'marker': 18});
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 460));
    await tester.pump(const Duration(milliseconds: 100));
    await waitFor(
      tester,
      () =>
          store.state('/server-control/list', account: 'demo-eu').error != null,
    );
    expect(store.assets.map((a) => a.name), oldNames);
    await tester.pumpAndSettle();
    await screenshot(tester, 'Flutter-02-RefreshFailureRetainsInstances');
    await qa('/qa/refresh', {'mode': 'ok', 'delay': 0, 'marker': 19});
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 460));
    await waitFor(
      tester,
      () => store.assets.any((a) => a.name.contains('refresh-19')),
    );
    await screenshot(tester, 'Flutter-03-Instances');
    await finish(tester);
  }

  Future<void> inventory(WidgetTester tester) async {
    await start(tester);
    await open(tester, find.byKey(const Key('tab.more')));
    await open(tester, find.text('服务器库存'));
    await waitFor(
      tester,
      () => find.byKey(const Key('plan.24ks-le-b')).evaluate().isNotEmpty,
    );
    expect(find.text('€20.83 / 月'), findsWidgets);
    await screenshot(tester, 'Flutter-04-Inventory');
    await store.setAppearance('dark');
    await screenshot(tester, 'Flutter-10-DarkInventory');
    await store.setAppearance('light');
    await tester.pumpAndSettle();
    await qa('/qa/inventory', {'mode': 'ok', 'delay': 1});
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 460));
    await tester.pump(const Duration(milliseconds: 100));
    await waitFor(
      tester,
      () => !store.state('/servers', account: 'demo-eu').loading,
    );
    expect(object(await qa('/qa/inventory'))['forced'], greaterThan(0));
    await open(tester, find.byKey(const Key('plan.24ks-le-b')));
    await open(tester, find.byKey(const Key('plan.order')));
    await open(tester, find.text('GRA'));
    await open(tester, find.byKey(const Key('order.submit')));
    await open(tester, find.byKey(const Key('operation.confirm')));
    await waitFor(tester, () => array(store.state('/queue').value).isNotEmpty);
    expect(
      object(array(store.state('/queue').value).last)['options'],
      contains('ram-32g-ddr4'),
    );
    await open(tester, find.byKey(const Key('tab.queue')));
    expect(find.text('24ks-le-b'), findsWidgets);
    await screenshot(tester, 'Flutter-05-Queue');
    await open(tester, find.byKey(const Key('tab.monitor')));
    expect(find.text('监控引擎'), findsOneWidget);
    await screenshot(tester, 'Flutter-06-Monitor');
    await open(tester, find.byKey(const Key('tab.instances')));
    await open(tester, find.byKey(const Key('asset.ns-demo-eu.example')));
    await open(tester, find.byKey(const Key('detail.电源')));
    await open(tester, find.byKey(const Key('native.InstallOS')));
    final buttons = find.byKey(const Key('operation.submit'));
    expect(buttons, findsOneWidget);
    await open(
      tester,
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == '系统模板 *',
      ),
    );
    await open(tester, find.text('debian13_64').last);
    await open(tester, buttons);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('operation.confirm')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const Key('operation.confirmTarget')),
      'ns-demo-eu.example',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('operation.confirm')))
          .onPressed,
      isNotNull,
    );
    await screenshot(tester, 'Flutter-07-NativeControl');
    await open(tester, find.text('取消'));
    await finish(tester);
  }

  Future<void> pairing(WidgetTester tester) async {
    await start(tester);
    await open(tester, find.byKey(const Key('tab.more')));
    await open(tester, find.text('API 设置'));
    await open(tester, find.byKey(const Key('native.SaveSettings')));
    await waitFor(
      tester,
      () =>
          find
              .byKey(const Key('input.defaultRetryInterval'))
              .evaluate()
              .isNotEmpty &&
          !store.state('/accounts').loading,
    );
    await tester.ensureVisible(
      find.byKey(const Key('input.defaultRetryInterval')),
    );
    await tester.enterText(
      find.byKey(const Key('input.defaultRetryInterval')),
      '73',
    );
    await open(tester, find.byKey(const Key('operation.submit')));
    await open(tester, find.byKey(const Key('operation.confirm')));
    await waitFor(tester, () => find.text('✓ 请求已成功提交').evaluate().isNotEmpty);
    final saved = object(await qa('/settings'));
    expect(saved['defaultRetryInterval'], 73);
    expect(saved['consumerKey'], 'qa-consumer');
    expect(saved['tgToken'], 'qa-telegram');
    await open(tester, find.byKey(const Key('tab.instances')));
    await open(tester, find.byKey(const Key('account.selector')));
    await open(tester, find.byKey(const Key('account.US')));
    await waitFor(
      tester,
      () => store.assets.any((a) => a.service == 'vps-demo-us.example'),
    );
    expect(store.selectedAccount, 'demo-us');
    expect(store.assets.any((a) => a.service == 'ns-demo-eu.example'), false);
    await screenshot(tester, 'Flutter-08-US-VPS');
    final issued = object(await qa('/app/pairing-codes', {}));
    final paired = await control.pair(
      fixture.address,
      text(issued['code']),
      'Flutter acceptance device',
    );
    await store.credentials.save(paired);
    final restored = await store.credentials.read();
    expect(restored?.deviceToken, true);
    expect(restored?.deviceId, paired.deviceId);
    // Fresh app shell preserves the independently stored device authorization.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    store.dispose();
    final catalog = Catalog(
      object(
        jsonDecode(await rootBundle.loadString('assets/NativeCatalog.json')),
      ),
    );
    store = PanelStore(catalog);
    await store.restore();
    expect(store.connection?.deviceToken, true);
    await tester.pumpWidget(OVHApp(store: store, restore: false));
    await tester.pumpAndSettle();
    await open(tester, find.byKey(const Key('tab.more')));
    await open(tester, find.text('连接与设备'));
    await tester.ensureVisible(find.byKey(const Key('connection.disconnect')));
    await tester.pumpAndSettle();
    final button = tester.getRect(
          find.byKey(const Key('connection.disconnect')),
        ),
        nav = tester.getRect(find.byType(NavigationBar));
    expect(button.bottom, lessThanOrEqualTo(nav.top));
    expect(
      button.top,
      greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom),
    );
    expect(
      find.byKey(const Key('connection.disconnect')).hitTestable(),
      findsOneWidget,
    );
    await screenshot(tester, 'Flutter-09-DisconnectReachable');
    await open(tester, find.byKey(const Key('connection.disconnect')));
    await open(tester, find.text('取消'));
    expect(store.connection, isNotNull);
    await open(tester, find.byKey(const Key('connection.disconnect')));
    await open(tester, find.byKey(const Key('operation.confirm')));
    await waitFor(tester, () => store.connection == null);
    expect(await store.credentials.read(), isNull);
    expect(find.byKey(const Key('pairing.address')), findsOneWidget);
    final newCode = object(await qa('/app/pairing-codes', {}));
    await Clipboard.setData(
      ClipboardData(text: '${fixture.address}/api/app/pair#${newCode['code']}'),
    );
    await open(tester, find.text('粘贴配对链接'));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('pairing.address')))
          .controller
          ?.text,
      fixture.address,
    );
    await screenshot(tester, 'Flutter-11-Pairing');
    await open(tester, find.byKey(const Key('pairing.connect')));
    await open(tester, find.byKey(const Key('operation.confirm')));
    await waitFor(
      tester,
      () => store.connection?.deviceToken == true && store.accounts.isNotEmpty,
    );
    await screenshot(tester, 'Flutter-12-PairedDashboard');
    await store.disconnect();
    await finish(tester);
  }

  testWidgets(
    'Native dashboard, refresh, inventory, controls, accounts and pairing',
    (tester) async {
      await dashboard(tester);
      await inventory(tester);
      await pairing(tester);
    },
  );
}
