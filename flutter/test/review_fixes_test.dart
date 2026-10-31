import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ovh_flutter/core/models.dart';
import 'package:ovh_flutter/core/upstream_compat.dart';
import 'package:ovh_flutter/ui/operation_page.dart';
import 'package:ovh_flutter/ui/pages.dart';
import 'core_test.dart' show loadCatalog, storeWith;
import 'upstream_compat_test.dart' show harness, clear;

const first = <String, dynamic>{
  'planCode': 'demo',
  'options': ['ram-64g'],
};
const all = <String, dynamic>{'planCode': 'demo', 'options': <String>[]};
const queueValues = <String, dynamic>{
  'datacenter': 'gra',
  'retryInterval': 60,
  'options': <String>[],
  'autoPay': false,
};
const task = <String, dynamic>{
  'id': 'q',
  'accountId': 'EU',
  'status': 'running',
};
final queueTarget = const Target('EU', 'EU').bind({'id': 'q'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'Subscription capabilities distinguish edit, pause, history and deletion',
    () {
      final catalog = loadCatalog();
      bool allowed(
        String method,
        String suffix,
        Json row,
        List<Json> rows,
        bool selectors,
      ) => subscriptionOperationSupported(
        catalog.op(method, '/monitor/subscriptions/:planCode$suffix'),
        row,
        rows,
        editAndPauseSelectors: selectors,
      );
      expect(allowed('PUT', '', all, [first, all], true), true);
      expect(allowed('POST', '/pause', all, [first, all], true), true);
      expect(allowed('DELETE', '', all, [first, all], true), false);
      expect(allowed('GET', '/history', all, [first, all], true), false);
      expect(allowed('GET', '/history', first, [first, all], true), false);
      expect(allowed('DELETE', '', first, [first, all], true), true);
      expect(allowed('PUT', '', all, [first, all], false), false);
      expect(allowed('POST', '/pause', all, [first, all], false), false);
      expect(allowed('DELETE', '', all, [all], false), true);
      expect(allowed('GET', '/history', all, [all], false), true);
    },
  );
  testWidgets(
    'v0.4.12 keeps edit and pause but hides unsafe deletion and history',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = storeWith((_) async => http.Response('{}', 200));
      store.state('/version').value = {'version': '0.4.12'};
      store.state('/monitor/subscriptions').value = [first, all];
      await tester.pumpWidget(harness(store, SubscriptionDetailPage(all)));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('native.UpdateSubscription')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('native.PauseSubscription')), findsOneWidget);
      expect(find.byKey(const Key('native.RemoveSubscription')), findsNothing);
      expect(
        find.byKey(const Key('native.GetSubscriptionHistory')),
        findsNothing,
      );
      await clear(tester, store);
    },
  );
  test(
    'Stale operation pages cannot bypass subscription safety guards',
    () async {
      var requests = 0;
      final store = storeWith((_) async {
        requests++;
        return http.Response('{}', 200);
      });
      store.state('/version').value = {'version': '0.4.12'};
      store.state('/monitor/subscriptions').value = [first, all];
      final target = const Target(
        'EU',
        'EU',
      ).bind({'planCode': 'demo', 'optionsKey': ''});
      for (final op in [
        loadCatalog().op('DELETE', '/monitor/subscriptions/:planCode'),
        loadCatalog().op('GET', '/monitor/subscriptions/:planCode/history'),
      ]) {
        await expectLater(
          store.execute(op, target, {}),
          throwsA(isA<PanelException>()),
        );
      }
      expect(requests, 0);
      store.dispose();
    },
  );
  testWidgets(
    'Contact change list and details preserve account and task for actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      http.Request? accepted;
      final store = storeWith((r) async {
        if (r.method == 'POST') accepted = r;
        return http.Response(
          jsonEncode(
            r.method == 'GET' &&
                    r.url.path == '/api/ovh/contact-change-requests/42'
                ? {
                    'status': 'success',
                    'data': {'id': 42, 'state': 'todo', 'domain': 'ns-demo'},
                  }
                : {},
          ),
          200,
        );
      });
      await tester.pumpWidget(
        harness(
          store,
          Scaffold(
            body: ResourceResults(
              value: {
                'status': 'success',
                'data': [
                  {'id': 42, 'state': 'todo', 'domain': 'ns-demo'},
                ],
                'total': 1,
                'failed': 0,
              },
              operation: loadCatalog().op(
                'GET',
                '/ovh/contact-change-requests',
              ),
              target: const Target('EU', 'EU'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final row in tester.widgetList<OperationRow>(
        find.byType(OperationRow),
      )) {
        expect(row.target.bindings['task_id'], 42);
        expect(row.target.account, 'EU');
      }
      expect(find.byType(OperationRow), findsNWidgets(4));
      await tester.tap(
        find.byKey(const Key('native.GetContactChangeRequestDetail')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('native.AcceptContactChangeRequest')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('native.RefuseContactChangeRequest')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('native.ResendContactChangeEmail')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('native.AcceptContactChangeRequest')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('input.token')),
        'synthetic-email-token',
      );
      await tester.tap(find.byKey(const Key('operation.submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('operation.confirm')));
      await tester.pumpAndSettle();
      expect(accepted?.url.path, '/api/ovh/contact-change-requests/42/accept');
      expect(accepted?.url.queryParameters['account'], 'EU');
      expect(jsonDecode(accepted!.body), {'token': 'synthetic-email-token'});
      await clear(tester, store);
    },
  );
  testWidgets('Running queue edits pause before saving and remain paused', (
    tester,
  ) async {
    final calls = <String>[];
    var status = 'running';
    final store = storeWith((r) async {
      if (r.method == 'GET' && r.url.path == '/api/queue') {
        return http.Response(
          jsonEncode([
            {...task, 'status': status},
          ]),
          200,
        );
      }
      if (r.method == 'PUT') {
        calls.add(r.url.path);
        if (r.url.path.endsWith('/status')) {
          expect(jsonDecode(r.body), {'status': 'paused'});
          status = 'paused';
        } else {
          expect(status, 'paused');
        }
      }
      return http.Response('{}', 200);
    });
    await tester.pumpWidget(
      harness(
        store,
        OperationPage(
          operation: loadCatalog().op('PUT', '/queue/:id'),
          target: queueTarget,
          seed: const {...queueValues, 'status': 'running'},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('operation.submit')));
    await tester.tap(find.byKey(const Key('operation.submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('operation.confirm')));
    await tester.pumpAndSettle();
    expect(calls, ['/api/queue/q/status', '/api/queue/q']);
    expect(status, 'paused');
    expect(find.text('✓ 请求已成功提交'), findsOneWidget);
    await clear(tester, store);
  });
  test('Paused queue edits do not issue a second pause or resume', () async {
    final writes = <String>[];
    final store = storeWith((r) async {
      if (r.method == 'PUT') writes.add(r.url.path);
      return http.Response(
        jsonEncode(
          r.url.path == '/api/queue'
              ? [
                  {...task, 'status': 'paused'},
                ]
              : {},
        ),
        200,
      );
    });
    await store.execute(
      loadCatalog().op('PUT', '/queue/:id'),
      queueTarget,
      queueValues,
    );
    expect(writes, ['/api/queue/q']);
    store.dispose();
  });
  test('Failed pause blocks configuration save', () async {
    final writes = <String>[];
    final store = storeWith((r) async {
      if (r.method == 'GET' && r.url.path == '/api/queue') {
        return http.Response(jsonEncode([task]), 200);
      }
      if (r.method == 'PUT') writes.add(r.url.path);
      return http.Response('{"error":"cannot pause"}', 409);
    });
    await expectLater(
      store.execute(
        loadCatalog().op('PUT', '/queue/:id'),
        queueTarget,
        queueValues,
      ),
      throwsA(isA<PanelException>()),
    );
    expect(writes, ['/api/queue/q/status']);
    store.dispose();
  });
  test(
    'Freshly completed, missing or mismatched queue targets are never changed',
    () async {
      for (final rows in [
        <Json>[
          {...task, 'status': 'completed'},
        ],
        <Json>[],
        <Json>[
          {...task, 'accountId': 'US'},
        ],
      ]) {
        final writes = <String>[];
        final store = storeWith((r) async {
          if (r.method == 'PUT') writes.add(r.url.path);
          return http.Response(jsonEncode(rows), 200);
        });
        store.state('/queue').value = [task];
        await expectLater(
          store.execute(
            loadCatalog().op('PUT', '/queue/:id'),
            queueTarget,
            queueValues,
          ),
          throwsA(isA<PanelException>()),
        );
        expect(writes, isEmpty);
        store.dispose();
      }
    },
  );
  test(
    'Connection change during queue preflight prevents writes to another panel',
    () async {
      final pending = Completer<http.Response>();
      var writes = 0;
      final store = storeWith((r) async {
        if (r.method == 'PUT') writes++;
        return pending.future;
      });
      final future = store.execute(
        loadCatalog().op('PUT', '/queue/:id'),
        queueTarget,
        queueValues,
      );
      final checked = expectLater(future, throwsA(isA<PanelException>()));
      await store.disconnect();
      store.connection = Connection.validated(
        'https://another.example',
        'synthetic',
      );
      pending.complete(http.Response(jsonEncode([task]), 200));
      await checked;
      expect(writes, 0);
      store.dispose();
    },
  );
  test('Invalid edit input is rejected before pausing a task', () async {
    var requests = 0;
    final store = storeWith((_) async {
      requests++;
      return http.Response('{}', 200);
    });
    await expectLater(
      store.execute(loadCatalog().op('PUT', '/queue/:id'), queueTarget, {
        ...queueValues,
        'retryInterval': 0,
      }),
      throwsA(isA<PanelException>()),
    );
    expect(requests, 0);
    store.dispose();
  });

  test(
    'Older queue refresh cannot overwrite the paused edit snapshot',
    () async {
      final oldResponse = Completer<http.Response>();
      final freshRefresh = Completer<void>();
      var reads = 0;
      final store = storeWith((r) async {
        if (r.method == 'GET' && r.url.path == '/api/queue') {
          reads++;
          if (reads == 1) {
            return oldResponse.future;
          }
          if (reads >= 3 && !freshRefresh.isCompleted) {
            freshRefresh.complete();
          }
          return http.Response(
            jsonEncode([
              {...task, 'status': reads == 2 ? 'running' : 'paused'},
            ]),
            200,
          );
        }
        return http.Response('{}', 200);
      });
      final oldLoad = store.load('/queue');
      final save = store.execute(
        loadCatalog().op('PUT', '/queue/:id'),
        queueTarget,
        queueValues,
      );
      try {
        await freshRefresh.future.timeout(const Duration(seconds: 2));
      } finally {
        oldResponse.complete(http.Response(jsonEncode([task]), 200));
      }
      await oldLoad;
      await save;
      expect(array(store.state('/queue').value).single['status'], 'paused');
      store.dispose();
    },
  );
}
