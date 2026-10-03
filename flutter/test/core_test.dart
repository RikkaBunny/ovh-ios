import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ovh_flutter/core/api.dart';
import 'package:ovh_flutter/core/models.dart';
import 'package:ovh_flutter/core/store.dart';
import 'package:ovh_flutter/ui/instances.dart';

class MemoryCredentials implements Credentials {
  Connection? value;
  @override
  Future<Connection?> read() async => value;
  @override
  Future<void> save(Connection connection) async => value = connection;
  @override
  Future<void> delete() async => value = null;
}

Catalog loadCatalog() => Catalog(
  object(jsonDecode(File('assets/NativeCatalog.json').readAsStringSync())),
);
PanelStore storeWith(Future<http.Response> Function(http.Request) handler) {
  final store = PanelStore(
    loadCatalog(),
    api: PanelApi(client: MockClient(handler)),
    credentials: MemoryCredentials(),
  );
  store.connection = Connection.validated('https://panel.example', 'test-key');
  store.selectedAccount = 'EU';
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Record sharing redacts credentials in nested objects and arrays', () {
    expect(
      redacted({
        'message': 'ok',
        'token': 'private',
        'nested': [
          {'password': 'private', 'id': 12},
        ],
      }),
      {
        'message': 'ok',
        'nested': [
          {'id': 12},
        ],
      },
    );
  });
  test(
    'Appearance survives restore independently of connection credentials',
    () async {
      final store = storeWith((_) async => http.Response('{}', 200));
      await store.setAppearance('dark');
      await store.setAppearance('invalid');
      expect(store.appearance.value, 'dark');
      store.dispose();
      final restored = storeWith((_) async => http.Response('{}', 200));
      await restored.restore();
      expect(restored.appearance.value, 'dark');
      restored.dispose();
    },
  );
  test('HTTPS origin excludes credentials, paths, fragments and queries', () {
    for (final input in [
      'http://panel.example',
      'https://user:pass@panel.example',
      'https://panel.example/path',
      'https://panel.example?key=foo',
      'https://panel.example#foo',
    ]) {
      expect(
        () => Connection.validated(input, 'test'),
        throwsA(isA<PanelException>()),
      );
    }
    expect(
      Connection.validated(' https://panel.example:8443/ ', ' test ').address,
      'https://panel.example:8443',
    );
  });
  test(
    'Pairing upgrades proxy HTTP and validates eight-character alphabet',
    () {
      final input = PairingInput.parse(
        'http://panel.example:8443/api/app/pair#abcd-2345',
      );
      expect(input.address, 'https://panel.example:8443');
      expect(input.code, 'ABCD2345');
      for (final input in [
        'https://user:pass@panel.example/api/app/pair#ABCD2345',
        'https://panel.example/api/app/pair?key=foo#ABCD2345',
        'https://panel.example/api/app/pair#O0I1ABCD',
        'https://panel.example/wrong#ABCD2345',
      ]) {
        expect(() => PairingInput.parse(input), throwsA(isA<PanelException>()));
      }
    },
  );
  test('Pairing sends code only in unauthenticated POST body', () async {
    final api = PanelApi(
      client: MockClient((r) async {
        expect(r.method, 'POST');
        expect(r.url.toString(), 'https://panel.example/api/app/pair');
        expect(r.url.hasFragment, false);
        expect(r.headers['Authorization'], isNull);
        expect(r.headers['X-API-Key'], isNull);
        expect(jsonDecode(r.body), {
          'code': 'ABCD2345',
          'deviceName': 'iPhone',
        });
        return http.Response(
          '{"success":true,"token":"synthetic-device-token","deviceId":123}',
          200,
        );
      }),
    );
    final result = await api.pair(
      'https://panel.example',
      'ABCD2345',
      'iPhone',
    );
    expect(result.deviceToken, true);
    expect(result.deviceId, 123);
    api.close();
  });
  test('Auth headers mutually exclude each other and fixed account wins', () {
    final api = PanelApi(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    final key = api.makeRequest(
      Connection.validated('https://panel.example', 'test-key'),
      '/stats?account=wrong',
      account: 'EU',
      query: {'account': 'malicious', 'type': 'traffic:download'},
    );
    expect(key.headers['Authorization'], isNull);
    expect(key.headers['X-API-Key'], 'test-key');
    expect(key.url.queryParameters['account'], 'EU');
    expect(key.followRedirects, false);
    final token = api.makeRequest(
      Connection.validated(
        'https://panel.example',
        'test-token',
        deviceToken: true,
      ),
      '/stats',
    );
    expect(token.headers['Authorization'], 'Bearer test-token');
    expect(token.headers['X-API-Key'], isNull);
    final none = api.makeRequest(
      Connection.validated('https://panel.example', 'test-key'),
      '/stats?account=wrong',
    );
    expect(none.url.queryParameters.containsKey('account'), false);
    api.close();
  });
  test(
    'Public inventory uses selected region without panel credentials',
    () async {
      final api = PanelApi(
        client: MockClient((r) async {
          expect(r.url.host, 'api.us.ovhcloud.com');
          expect(r.headers['Authorization'], isNull);
          expect(r.headers['X-API-Key'], isNull);
          return http.Response('[]', 200);
        }),
      );
      await api.stock(
        Account({'id': 'US', 'name': 'US', 'endpoint': 'ovh-us', 'zone': 'US'}),
        Connection.validated('https://panel.example', 'test-key'),
      );
      api.close();
    },
  );
  test('401 invalidates credentials even when response is not JSON', () async {
    final store = storeWith((_) async => http.Response('unauthorized', 401));
    await store.load('/stats');
    expect(store.connection, isNull);
    store.dispose();
  });
  test('Server message cancelled remains a genuine error', () async {
    final api = PanelApi(
      client: MockClient(
        (_) async => http.Response('{"error":"cancelled"}', 503),
      ),
    );
    await expectLater(
      api.request(
        Connection.validated('https://panel.example', 'test'),
        '/servers',
      ),
      throwsA(
        isA<PanelException>().having((e) => e.message, 'message', 'cancelled'),
      ),
    );
    api.close();
  });
  test(
    'All 226 operation descriptors resolve complete target and typed fields',
    () {
      final catalog = loadCatalog();
      expect(catalog.operations.length, 226);
      expect(catalog.operations.map((o) => o.id).toSet().length, 226);
      for (final op in catalog.operations) {
        final values = <String, dynamic>{};
        for (final f in op.fields) {
          values[f.key] = switch (f.kind) {
            'number' => 1,
            'toggle' => false,
            'list' => <String>[],
            'object' => <String, dynamic>{},
            'objects' => <Json>[],
            _ => f.choices.firstOrNull ?? 'test',
          };
        }
        final result = op.resolve(
          values,
          const Target('EU', '演示', service: 'ns-demo.example'),
        );
        expect(result.path, isNot(contains(':')));
        expect(result.path, isNot(contains('*')));
        expect(result.body == null, op.read);
      }
    },
  );
  test('Service path escaping and quantity/interval limits', () {
    final catalog = loadCatalog();
    final read = catalog.op('GET', '/server-control/:service_name/serviceinfo');
    expect(
      read.resolve({}, const Target('EU', '演示', service: 'a/b.example')).path,
      contains('a%2Fb.example'),
    );
    final op = catalog.op('POST', '/monitor/subscriptions');
    expect(
      () => op.resolve({
        'planCode': 'test',
        'quantity': 21,
      }, const Target('EU', '演示')),
      throwsA(isA<PanelException>()),
    );
    final retry = catalog.op('PUT', '/queue/:id/interval');
    expect(
      () => retry.resolve({
        'retryInterval': 0,
      }, const Target('EU', '演示', bindings: {'id': 'test'})),
      throwsA(isA<PanelException>()),
    );
  });
  test(
    'Dangerous reinstall and termination require typed service confirmation',
    () {
      final catalog = loadCatalog();
      expect(
        catalog
            .op('POST', '/server-control/:service_name/install')
            .typedConfirmation,
        true,
      );
      expect(
        catalog
            .op('POST', '/vps-control/:service_name/reinstall')
            .typedConfirmation,
        true,
      );
      expect(
        catalog
            .op('POST', '/server-control/:service_name/reboot')
            .typedConfirmation,
        false,
      );
      expect(
        catalog
            .op('POST', '/vps-control/:service_name/reinstall')
            .fields
            .firstWhere((f) => f.key == 'templateId')
            .kind,
        'text',
      );
    },
  );
  test('Unavailable and comingSoon are not purchasable inventory', () {
    for (final status in ['1H', '72H-high', '24H-low']) {
      expect(orderable(status), true);
    }
    for (final status in [
      'comingSoon',
      'unavailable',
      'unknown',
      '1H-extra',
      'H',
    ]) {
      expect(orderable(status), false);
    }
  });
  test(
    'Catalog sums monthly addon and installation separately using currency',
    () {
      final json = {
        'locale': {'currencyCode': 'USD'},
        'plans': [
          {
            'planCode': 'test',
            'pricings': [
              {
                'intervalUnit': 'month',
                'interval': 1,
                'mode': 'default',
                'capacities': [],
                'price': 2000000000,
                'tax': 400000000,
              },
              {
                'mode': 'default',
                'capacities': ['installation'],
                'price': 1000000000,
                'tax': 200000000,
              },
            ],
          },
        ],
        'addons': [
          {
            'planCode': 'ram',
            'pricings': [
              {
                'intervalUnit': 'month',
                'interval': 1,
                'mode': 'default',
                'capacities': [],
                'price': 500000000,
                'tax': 100000000,
              },
            ],
          },
        ],
      };
      final price = planPrice(json, 'test', ['ram'])!;
      expect(price.monthly, 25);
      expect(price.tax, 5);
      expect(price.installation, 10);
      expect(price.installationTax, 2);
      expect(price.currency, 'USD');
    },
  );
  test('Real zero resources differ from unknown and invalid capacities', () {
    expect(
      resourcePercent({
        'cpu': {'cores': 4, 'percent': 0},
      }, 'cpu'),
      0,
    );
    expect(
      resourcePercent({
        'cpu': {'cores': 0, 'percent': 0},
      }, 'cpu'),
      isNull,
    );
    expect(
      resourcePercent({
        'memory': {'percent': 40, 'usedBytes': 40, 'totalBytes': 100},
      }, 'memory'),
      40,
    );
    expect(
      resourcePercent({
        'memory': {'percent': 0, 'usedBytes': 0, 'totalBytes': 0},
      }, 'memory'),
      isNull,
    );
    expect(bytes(1024), '1.0 KB');
  });
  test('OVH nested bandwidth values convert bps once to Mbps', () {
    final points = trafficPoints(
      {
        'interfaces': [
          {
            'mac': 'aa',
            'data': [
              {
                'timestamp': 1,
                'value': {'value': 8000000, 'unit': 'bps'},
              },
              {'timestamp': 2, 'value': null},
            ],
          },
        ],
      },
      'aa',
      true,
    );
    expect(points.length, 1);
    expect(points.single.value, 8);
  });
  test(
    'Cache warning keeps the actual age in Chinese',
    () => expect(
      cacheWarning('Using expired cache (225 minutes old)'),
      contains('225 分钟前'),
    ),
  );
  test(
    'Repeated refresh joins one request and completes after caller stops awaiting',
    () async {
      final response = Completer<http.Response>();
      var calls = 0;
      final store = storeWith((_) {
        calls++;
        return response.future;
      });
      final first = store.load('/stats');
      final second = store.load('/stats');
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      response.complete(http.Response('{"totalServers":9}', 200));
      await Future.wait([first, second]);
      expect(object(store.state('/stats').value)['totalServers'], 9);
      store.dispose();
    },
  );
  test(
    'Genuine refresh error preserves last value and successful timestamp',
    () async {
      var bad = false;
      final store = storeWith(
        (_) async => bad
            ? http.Response('{"error":"temporary outage"}', 503)
            : http.Response('{"totalServers":9}', 200),
      );
      await store.load('/stats');
      final updated = store.state('/stats').updated;
      bad = true;
      await store.load('/stats');
      expect(object(store.state('/stats').value)['totalServers'], 9);
      expect(store.state('/stats').updated, updated);
      expect(store.state('/stats').error, contains('temporary outage'));
      store.dispose();
    },
  );
  test(
    'Old account and disconnected responses cannot repopulate current data',
    () async {
      final response = Completer<http.Response>();
      final store = storeWith((_) => response.future);
      final old = store.load(
        '/server-control/list',
        account: 'EU',
        activeScope: true,
      );
      store.selectedAccount = 'US';
      response.complete(
        http.Response('{"servers":[{"serviceName":"old"}]}', 200),
      );
      await old;
      expect(store.assets, isEmpty);
      expect(store.state('/server-control/list', account: 'EU').value, isNull);
      store.dispose();
      final second = Completer<http.Response>();
      final other = storeWith((_) => second.future);
      final pending = other.load('/stats');
      await other.disconnect();
      second.complete(http.Response('{"totalServers":999}', 200));
      await pending;
      expect(other.connection, isNull);
      expect(other.state('/stats').value, isNull);
      other.dispose();
    },
  );
  test(
    'Forced catalog supersedes normal request and shares its resource identity',
    () async {
      final requests = <Completer<http.Response>>[];
      final store = storeWith((_) {
        final c = Completer<http.Response>();
        requests.add(c);
        return c.future;
      });
      final normal = store.load(
        '/servers',
        account: 'EU',
        query: {'forceRefresh': 'false', 'showApiServers': 'false'},
      );
      await Future<void>.delayed(Duration.zero);
      final forced = store.load(
        '/servers',
        account: 'EU',
        query: {'forceRefresh': 'true', 'showApiServers': 'true'},
      );
      await Future<void>.delayed(Duration.zero);
      expect(requests.length, 2);
      requests[1].complete(http.Response('{"servers":["new"]}', 200));
      await forced;
      requests[0].complete(http.Response('{"servers":["old"]}', 200));
      await normal;
      expect(object(store.state('/servers', account: 'EU').value)['servers'], [
        'new',
      ]);
      store.dispose();
    },
  );
  test('Resource fetch failure switches metrics to unknown', () async {
    var bad = false;
    final store = storeWith(
      (_) async => bad
          ? http.Response('{"error":"offline"}', 503)
          : http.Response('{"cpu":{"cores":4,"percent":20}}', 200),
    );
    await store.load('/system/metrics', unknownOnFailure: true);
    bad = true;
    await store.load('/system/metrics', unknownOnFailure: true);
    expect(store.state('/system/metrics').value, isNull);
    store.dispose();
  });
}
