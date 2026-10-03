import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ovh_flutter/core/instance_metrics.dart';
import 'package:ovh_flutter/core/models.dart';
import 'core_test.dart' show storeWith;

final dedicated = Asset({'serviceName': 'panel.example', 'name': '独服'});
final vps = Asset({'serviceName': 'vps.example'}, vps: true);
Json reading(String account, Asset asset, num percent) => {
  ...unavailableInstanceMetrics(account, asset, ''),
  'status': 'available',
  'metrics': {
    'cpu': {'percent': percent, 'cores': 4},
    'memory': {'percent': 25, 'usedBytes': 1, 'totalBytes': 4},
    'disk': {'percent': 50, 'usedBytes': 2, 'totalBytes': 4},
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Instance telemetry rejects host, wrong account, service, and kind', () {
    for (final data in [
      {'cpu': {}, 'memory': {}, 'disk': {}},
      reading('US', dedicated, 1),
      {...reading('EU', dedicated, 1), 'service': vps.service},
      {...reading('EU', dedicated, 1), 'kind': 'vps'},
    ]) {
      expect(
        () => checkedInstanceMetrics(data, 'EU', dedicated),
        throwsA(isA<PanelException>()),
      );
    }
  });
  test('Unavailable instance is explicit and never fabricated zero usage', () {
    final value = checkedInstanceMetrics(
      unavailableInstanceMetrics('US', vps, 'NO_AGENT'),
      'US',
      vps,
    );
    expect(value['status'], 'unavailable');
    expect(value.containsKey('metrics'), false);
  });
  test(
    'Late previous-account response never populates new account resources',
    () async {
      final slow = Completer<http.Response>();
      final store = storeWith(
        (request) async => request.url.queryParameters['account'] == 'EU'
            ? slow.future
            : http.Response(jsonEncode(reading('US', vps, 8)), 200),
      );
      store.state('/server-control/list', account: 'EU').value = {
        'servers': [dedicated.raw],
      };
      final previous = store.refreshInstanceMetrics();
      store.selectedAccount = 'US';
      store.accountRevision++;
      store.state('/vps-control/list', account: 'US').value = {
        'vps': [vps.raw],
      };
      await store.refreshInstanceMetrics();
      slow.complete(
        http.Response(jsonEncode(reading('EU', dedicated, 91)), 200),
      );
      await previous;
      expect(
        object(
          object(store.instanceMetrics!.value)['metrics'],
        )['cpu']['percent'],
        8,
      );
      expect(
        store
            .state(
              '/instance-metrics',
              account: 'EU',
              query: store.resourceQuery(dedicated),
            )
            .value,
        isNull,
      );
      store.dispose();
    },
  );
  test(
    'Instance switching uses independent cache and remembers choice per account',
    () async {
      final requests = <Map<String, String>>[];
      final store = storeWith((request) async {
        requests.add(request.url.queryParameters);
        final asset = request.url.queryParameters['kind'] == 'vps'
            ? vps
            : dedicated;
        return http.Response(
          jsonEncode(reading('EU', asset, asset.vps ? 9 : 80)),
          200,
        );
      });
      store.state('/server-control/list', account: 'EU').value = {
        'servers': [dedicated.raw],
      };
      store.state('/vps-control/list', account: 'EU').value = {
        'vps': [vps.raw],
      };
      await store.refreshInstanceMetrics();
      await store.selectResourceAsset(store.resourceAssetId(vps));
      expect(store.resourceAsset!.vps, true);
      expect(
        object(
          object(store.instanceMetrics!.value)['metrics'],
        )['cpu']['percent'],
        9,
      );
      expect(
        requests.every(
          (q) =>
              q['account'] == 'EU' && q['service'] != null && q['kind'] != null,
        ),
        true,
      );
      store.selectedAccount = 'US';
      expect(store.resourceAsset, isNull);
      expect(store.instanceMetrics, isNull);
      store.selectedAccount = 'EU';
      expect(store.resourceAsset!.service, vps.service);
      store.dispose();
    },
  );
  test(
    'Old backend without instance endpoint never falls back to host metrics',
    () async {
      final paths = <String>[];
      final store = storeWith((request) async {
        paths.add(request.url.path);
        return http.Response('{"error":"not supported"}', 404);
      });
      store.state('/server-control/list', account: 'EU').value = {
        'servers': [dedicated.raw],
      };
      await store.refreshInstanceMetrics();
      expect(
        object(store.instanceMetrics!.value)['reason'],
        'BACKEND_UNSUPPORTED',
      );
      expect(paths, ['/api/instance-metrics']);
      expect(store.connection, isNotNull);
      store.dispose();
    },
  );
  test(
    'Failed refresh clears old telemetry instead of implying current values',
    () async {
      var offline = false;
      final store = storeWith(
        (_) async => offline
            ? http.Response('{"error":"offline"}', 503)
            : http.Response(jsonEncode(reading('EU', dedicated, 5)), 200),
      );
      store.state('/server-control/list', account: 'EU').value = {
        'servers': [dedicated.raw],
      };
      await store.refreshInstanceMetrics();
      offline = true;
      await store.refreshInstanceMetrics();
      expect(store.instanceMetrics!.value, isNull);
      expect(store.instanceMetrics!.error, 'offline');
      store.dispose();
    },
  );
}
