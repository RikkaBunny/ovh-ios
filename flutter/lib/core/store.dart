import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'models.dart';

abstract class Credentials {
  Future<Connection?> read();
  Future<void> save(Connection connection);
  Future<void> delete();
}

class SecureCredentials implements Credentials {
  static const legacy = MethodChannel('ovh_cp/legacy_connection');
  final storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static const key = 'ovh.flutter.connection';
  @override
  Future<Connection?> read() async {
    final value = await storage.read(key: key);
    if (value != null) return Connection.fromJson(object(jsonDecode(value)));
    if (defaultTargetPlatform != TargetPlatform.iOS) return null;
    final previous = await legacy.invokeMapMethod<String, dynamic>('read');
    if (previous == null) return null;
    final connection = Connection.fromJson(previous);
    // Preserve the old credential until the new Keychain write succeeds.
    await storage.write(key: key, value: jsonEncode(connection.toJson()));
    final preferences = await SharedPreferences.getInstance();
    if (!preferences.containsKey('ovh.account')) {
      await preferences.setString('ovh.account', text(previous['account']));
    }
    if (!preferences.containsKey('ovh.appearance')) {
      await preferences.setString(
        'ovh.appearance',
        text(previous['appearance'], 'system'),
      );
    }
    await legacy.invokeMethod<void>('clear');
    return connection;
  }

  @override
  Future<void> save(Connection connection) =>
      storage.write(key: key, value: jsonEncode(connection.toJson()));
  @override
  Future<void> delete() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await legacy.invokeMethod<void>('clear');
    }
    await storage.delete(key: key);
  }
}

class ResourceState {
  dynamic value;
  String? error;
  List<String> notices = [];
  bool loading = false;
  DateTime? updated;
  int revision = 0;
  Future<void>? pending;
  bool forced = false;
}

class PanelStore extends ChangeNotifier {
  final PanelApi api;
  final Credentials credentials;
  final Catalog catalog;
  final appearance = ValueNotifier<String>('system');
  Connection? connection;
  List<Account> accounts = [];
  String selectedAccount = '';
  String? connectionError;
  bool connecting = false;
  int session = 0;
  int mutations = 0;
  int accountRevision = 0;
  final Map<String, ResourceState> _resources = {};
  PanelStore(this.catalog, {PanelApi? api, Credentials? credentials})
    : api = api ?? PanelApi(),
      credentials = credentials ?? SecureCredentials();
  Account? get activeAccount =>
      accounts.where((v) => v.id == selectedAccount).firstOrNull;
  Target get target => Target(selectedAccount, activeAccount?.name ?? '当前账户');
  String identity(
    String path, {
    String? account,
    Map<String, String> query = const {},
  }) {
    final scope = {...query}..remove('forceRefresh');
    if (path == '/servers') scope.remove('showApiServers');
    final entries = scope.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return '$session|$path|${account ?? ''}|${entries.map((e) => '${e.key}=${e.value}').join('&')}';
  }

  ResourceState state(
    String path, {
    String? account,
    Map<String, String> query = const {},
  }) => _resources.putIfAbsent(
    identity(path, account: account, query: query),
    ResourceState.new,
  );
  Future<void> restore() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      connection = await credentials.read();
      appearance.value = preferences.getString('ovh.appearance') ?? 'system';
      selectedAccount = preferences.getString('ovh.account') ?? '';
      notifyListeners();
      if (connection != null) await refreshOverview();
    } catch (error) {
      connectionError = '无法恢复本机连接：$error';
      notifyListeners();
    }
  }

  Future<void> setAppearance(String value) async {
    if (!{'system', 'light', 'dark'}.contains(value)) return;
    appearance.value = value;
    await (await SharedPreferences.getInstance()).setString(
      'ovh.appearance',
      value,
    );
  }

  Future<void> connect(
    String address,
    String secret, {
    bool pair = false,
    String deviceName = '手机 · OVH CP',
  }) async {
    if (connecting) return;
    connecting = true;
    connectionError = null;
    notifyListeners();
    final ticket = session;
    try {
      final candidate = pair
          ? await api.pair(address, secret, deviceName)
          : Connection.validated(address, secret);
      await api.request(candidate, '/health');
      if (session != ticket) return;
      await credentials.save(candidate);
      connection = candidate;
      session++;
      _resources.clear();
      await refreshOverview();
    } catch (error) {
      if (session == ticket || connection != null) connectionError = '$error';
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    session++;
    connection = null;
    accounts = [];
    selectedAccount = '';
    _resources.clear();
    connectionError = null;
    await credentials.delete();
    await (await SharedPreferences.getInstance()).remove('ovh.account');
    notifyListeners();
  }

  Future<void> select(String id) async {
    if (id == selectedAccount || !accounts.any((a) => a.id == id)) return;
    selectedAccount = id;
    accountRevision++;
    for (final resource in _resources.values) {
      resource.revision++;
      resource.loading = false;
      resource.pending = null;
    }
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString('ovh.account', id);
    await refreshOverview(includeAccounts: false);
  }

  Future<void> refreshOverview({bool includeAccounts = true}) async {
    if (connection == null) return;
    if (includeAccounts) {
      await load('/accounts');
      if (connection == null) return;
      final value = state('/accounts').value;
      if (value != null) {
        accounts = array(
          object(value)['accounts'],
        ).map((j) => Account(object(j))).toList();
        if (!accounts.any((a) => a.id == selectedAccount)) {
          selectedAccount =
              accounts.where((a) => a.isDefault).firstOrNull?.id ??
              accounts.firstOrNull?.id ??
              '';
        }
        notifyListeners();
      }
    }
    final account = selectedAccount;
    await Future.wait([
      load('/stats'),
      load('/queue'),
      if (account.isNotEmpty)
        load('/server-control/list', account: account, activeScope: true),
      if (account.isNotEmpty)
        load('/vps-control/list', account: account, activeScope: true),
    ]);
  }

  List<Asset> get assets => [
    ...array(
      object(
        state('/server-control/list', account: selectedAccount).value,
      )['servers'],
    ).map((j) => Asset(object(j))),
    ...array(
      object(state('/vps-control/list', account: selectedAccount).value)['vps'],
    ).map((j) => Asset(object(j), vps: true)),
  ];
  Future<void> load(
    String path, {
    String? account,
    Map<String, String> query = const {},
    bool activeScope = false,
    bool unknownOnFailure = false,
    Future<ApiResult> Function(Connection)? fetch,
  }) async {
    final current = connection;
    if (current == null) return;
    final resource = state(path, account: account, query: query);
    final force = query['forceRefresh'] == 'true';
    if (resource.pending != null && (!force || resource.forced)) {
      await resource.pending;
      return;
    }
    final ticket = ++resource.revision,
        sessionTicket = session,
        accountTicket = accountRevision;
    resource.loading = true;
    resource.error = null;
    resource.forced = force;
    notifyListeners();
    Future<void> work() async {
      bool valid() =>
          ticket == resource.revision &&
          session == sessionTicket &&
          identical(connection, current) &&
          (!activeScope ||
              selectedAccount == account && accountRevision == accountTicket);
      try {
        final result = fetch == null
            ? await api.request(current, path, account: account, query: query)
            : await fetch(current);
        if (!valid()) return;
        resource.value = result.value;
        resource.notices = result.notices;
        resource.updated = DateTime.now();
      } catch (error) {
        if (!valid()) return;
        if (error is PanelException && error.status == 401 && fetch == null) {
          await disconnect();
          return;
        }
        resource.error = '$error';
        if (unknownOnFailure) resource.value = null;
      } finally {
        if (ticket == resource.revision) {
          resource.loading = false;
          resource.pending = null;
        }
        notifyListeners();
      }
    }

    final pending = work();
    resource.pending = pending;
    await pending;
  }

  Future<ApiResult> execute(
    Operation operation,
    Target target,
    Json values,
  ) async {
    final current = connection;
    if (current == null) throw const PanelException('请先连接面板');
    final ticket = session, resolved = operation.resolve(values, target);
    final chosen = target.service != null
        ? target.account
        : text(values['account_id'], text(values['accountId'], target.account));
    try {
      final result = await api.request(
        current,
        resolved.path,
        account: chosen,
        method: operation.method,
        body: resolved.body,
        query: resolved.query,
      );
      if (ticket != session || !identical(current, connection)) {
        throw const PanelException('连接已改变，请重新进入页面');
      }
      if (!operation.read) {
        mutations++;
        notifyListeners();
        await refreshOverview(
          includeAccounts: operation.path.startsWith('/accounts'),
        );
      }
      return result;
    } on PanelException catch (error) {
      if (error.status == 401 && identical(connection, current)) {
        await disconnect();
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    api.close();
    appearance.dispose();
    super.dispose();
  }
}
