import 'dart:convert';

typedef Json = Map<String, dynamic>;
Json object(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<dynamic> array(dynamic value) => value is List ? value : [];
String text(dynamic value, [String fallback = '']) =>
    value == null ? fallback : value.toString();
String pretty(dynamic value) =>
    const JsonEncoder.withIndent('  ').convert(value);
bool secretField(String key) => {
  'appKey',
  'appSecret',
  'consumerKey',
  'tgToken',
  'token',
  'deviceToken',
  'apiKey',
  'password',
}.contains(key);

dynamic redacted(dynamic value) => value is Map
    ? {
        for (final entry in value.entries)
          if (!secretField(text(entry.key)))
            text(entry.key): redacted(entry.value),
      }
    : value is List
    ? value.map(redacted).toList()
    : value;

class PanelException implements Exception {
  final String message;
  final int? status;
  const PanelException(this.message, [this.status]);
  @override
  String toString() => message;
}

class Connection {
  final String address, secret;
  final bool deviceToken;
  final int? deviceId;
  const Connection(
    this.address,
    this.secret, {
    this.deviceToken = false,
    this.deviceId,
  });
  factory Connection.validated(
    String address,
    String secret, {
    bool deviceToken = false,
    int? deviceId,
  }) {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const PanelException(
        '请输入完整的 HTTPS 面板地址，例如 https://panel.example.com',
      );
    }
    if (secret.trim().isEmpty) throw const PanelException('请输入面板访问密钥');
    return Connection(
      uri.replace(path: '').toString(),
      secret.trim(),
      deviceToken: deviceToken,
      deviceId: deviceId,
    );
  }
  factory Connection.fromJson(Json json) => Connection.validated(
    text(json['address']),
    text(json['secret']),
    deviceToken: json['deviceToken'] == true,
    deviceId: json['deviceId'] as int?,
  );
  Json toJson() => {
    'address': address,
    'secret': secret,
    'deviceToken': deviceToken,
    'deviceId': deviceId,
  };
}

class PairingInput {
  final String address, code;
  const PairingInput(this.address, this.code);
  static String normalizeCode(String input) {
    final code = input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$').hasMatch(code)) {
      throw const PanelException('请输入网页生成的 8 位配对码');
    }
    return code;
  }

  factory PairingInput.parse(String input) {
    var uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.path != '/api/app/pair' ||
        uri.hasQuery ||
        !uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw const PanelException('这不是 OVH 面板的配对二维码');
    }
    if (uri.scheme == 'http') uri = uri.replace(scheme: 'https');
    final code = normalizeCode(uri.fragment);
    final address = Connection.validated(
      uri
          .replace(path: '', fragment: '')
          .toString()
          .replaceFirst(RegExp(r'#$'), ''),
      'validation',
    ).address;
    return PairingInput(address, code);
  }
}

class Account {
  final String id, name, endpoint, zone;
  final bool isDefault;
  Account(Json json)
    : id = text(json['id']),
      name = text(json['name']),
      endpoint = text(json['endpoint']),
      zone = text(json['zone']),
      isDefault = json['isDefault'] == true;
  String get region => endpoint.endsWith('-us')
      ? 'US'
      : endpoint.endsWith('-ca')
      ? 'CA'
      : 'EU';
}

class Asset {
  final Json raw;
  final bool vps;
  Asset(this.raw, {this.vps = false});
  String get service => text(raw['serviceName']);
  String get name => text(raw[vps ? 'displayName' : 'name'], service);
  String get root => vps ? '/vps-control' : '/server-control';
  String get state => text(raw['state'], 'unknown');
  String get location => vps
      ? (text(raw['zone']).contains('west-or')
            ? '俄勒冈 · 美国'
            : text(raw['zone'], '未知机房'))
      : text(raw['datacenter'], '未知机房').toUpperCase();
  String get specification => vps
      ? '${text(raw['vcore'], '—')} vCPU · ${((raw['memoryMB'] as num? ?? 0) / 1024).toStringAsFixed(0)} GB · ${text(raw['diskGB'], '—')} GB'
      : text(raw['commercialRange'], '配置未获取');
  bool get healthy =>
      {'ok', 'active', 'running'}.contains(state) &&
      raw['error'] == null &&
      raw['svcInfoError'] == null;
  String get stateLabel =>
      {
        'ok': '正常',
        'active': '正常',
        'running': '运行中',
        'stopped': '已关机',
        'suspended': '已暂停',
        'installing': '安装中',
        'unknown': '状态未知',
      }[state] ??
      state;
}

class Target {
  final String account, name;
  final String? service;
  final Json bindings;
  const Target(
    this.account,
    this.name, {
    this.service,
    this.bindings = const {},
  });
  Target bind(Json values) => Target(
    account,
    name,
    service: service,
    bindings: {...bindings, ...values},
  );
}

class FieldSpec {
  final String key, label, kind, location;
  final bool required;
  final List<String> choices;
  final List<FieldSpec> children;
  FieldSpec(Json json)
    : key = text(json['key']),
      label = text(json['label']),
      kind = text(json['kind']),
      location = text(json['location']),
      required = json['required'] == true,
      choices = array(json['choices']).map(text).toList(),
      children = array(
        json['children'],
      ).map((v) => FieldSpec(object(v))).toList();
}

class Operation {
  final String id, title, group, scope, method, path, handler;
  final bool danger;
  final List<FieldSpec> fields;
  Operation(Json json)
    : id = text(json['id']),
      title = text(json['title']),
      group = text(json['group']),
      scope = text(json['scope']),
      method = text(json['method']),
      path = text(json['path']),
      handler = text(json['handler']),
      danger = json['danger'] == true,
      fields = array(json['fields']).map((v) => FieldSpec(object(v))).toList();
  bool get read => method == 'GET';
  bool get typedConfirmation =>
      danger &&
      !read &&
      [
        'install',
        'reinstall',
        'terminate',
        'hardware/replace',
        'snapshot/revert',
      ].any((s) => path.endsWith('/$s'));
  String? get globalTarget => {
    '/queue/clear': '所有账户的抢购队列',
    '/purchase-history': '所有账户的抢购历史',
    '/monitor/subscriptions/clear': '全部服务器监控订阅',
    '/vps-monitor/subscriptions/clear': '全部 VPS 监控订阅',
    '/logs': '整个面板的日志',
  }[path];
  ({String path, Map<String, String> query, Json? body}) resolve(
    Json values,
    Target target,
  ) {
    var route = path;
    if (target.service != null) {
      route = route.replaceAll(
        ':service_name',
        Uri.encodeComponent(target.service!),
      );
    }
    final query = <String, String>{}, body = <String, dynamic>{};
    for (final field in fields) {
      final value = target.bindings.containsKey(field.key)
          ? target.bindings[field.key]
          : values[field.key];
      final empty = value == null || value == '';
      if (empty && field.required) throw PanelException('请填写${field.label}');
      if (value == null || (empty && field.location != 'body')) continue;
      if (field.kind == 'number' && value is! num) {
        throw PanelException('${field.label}必须是数字');
      }
      if (field.key == 'quantity' &&
          value is num &&
          (value < 1 || value > 20 || value != value.round())) {
        throw const PanelException('每个机房数量必须在 1～20 之间');
      }
      if ([
            'retryInterval',
            'interval',
            'check_interval',
            'defaultRetryInterval',
            'quickOrderRetryInterval',
          ].contains(field.key) &&
          value is num &&
          (value < 1 || value > 86400 || value != value.round())) {
        throw const PanelException('间隔必须在 1～86400 秒之间');
      }
      if (field.location == 'path') {
        route = route
            .replaceAll(':${field.key}', Uri.encodeComponent(text(value)))
            .replaceAll('*${field.key}', Uri.encodeComponent(text(value)));
      } else if (field.location == 'query') {
        query[field.key] = text(value);
      } else {
        body[field.key] = value;
      }
    }
    if (route.contains(':') || route.contains('*')) {
      throw const PanelException('请选择完整的操作目标');
    }
    return (
      path: route,
      query: query,
      body: read
          ? null
          : path == '/settings'
          ? {...values, ...body}
          : body,
    );
  }
}

class Catalog {
  final List<Operation> operations;
  final Json labels;
  final List<Json> subsidiaries;
  final String commit;
  Catalog(Json json)
    : operations = array(
        json['operations'],
      ).map((v) => Operation(object(v))).toList(),
      labels = object(json['labels']),
      subsidiaries = array(json['subsidiaries']).map(object).toList(),
      commit = text(json['commit']);
  Operation op(String method, String path) =>
      operations.firstWhere((o) => o.method == method && o.path == path);
  String label(String key) => text(labels[key], key);
}

bool orderable(String status) =>
    RegExp(r'^\d+H(-high|-low)?$').hasMatch(status);
String stockLabel(String status) => orderable(status)
    ? '有货 · $status'
    : {
            'unavailable': '无货',
            'comingSoon': '即将上架',
            'unknown': '未知',
            '': '未查询',
          }[status] ??
          status;
String cacheWarning(String input) {
  if (!input.startsWith('Using expired cache')) return input;
  final age = RegExp(r'\d+').firstMatch(input)?.group(0);
  return '当前展示旧目录缓存${age == null ? '' : '（$age 分钟前）'}，请刷新或进入详情查询实时库存。';
}

double? resourcePercent(Json value, String kind) {
  final data = object(value[kind]), percent = data['percent'];
  if (percent is! num || !percent.isFinite || percent < 0 || percent > 100) {
    return null;
  }
  if (kind == 'cpu') {
    return (data['cores'] is num && data['cores'] > 0)
        ? percent.toDouble()
        : null;
  }
  final total = data['totalBytes'], used = data['usedBytes'];
  return total is num &&
          used is num &&
          total.isFinite &&
          used.isFinite &&
          total > 0 &&
          used >= 0 &&
          used <= total
      ? percent.toDouble()
      : null;
}

String bytes(dynamic value) {
  if (value is! num || !value.isFinite || value < 0) return '—';
  var amount = value.toDouble(), index = 0;
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  while (amount >= 1024 && index < units.length - 1) {
    amount /= 1024;
    index++;
  }
  return '${amount.toStringAsFixed(index == 0 ? 0 : 1)} ${units[index]}';
}

class PlanPrice {
  final double monthly, tax, installation, installationTax;
  final String currency;
  const PlanPrice(
    this.monthly,
    this.tax,
    this.installation,
    this.installationTax,
    this.currency,
  );
  String money(double amount) =>
      '${{'USD': 'US\$', 'EUR': '€', 'GBP': '£', 'CAD': 'CA\$'}[currency] ?? '$currency '}${amount.toStringAsFixed(2)}';
  String get label => '${money(monthly)} / 月';
}

PlanPrice? planPrice(Json catalog, String plan, List<String> options) {
  final base = array(
    catalog['plans'],
  ).map(object).where((v) => v['planCode'] == plan).firstOrNull;
  if (base == null) return null;
  final records = [
    base,
    ...array(
      catalog['addons'],
    ).map(object).where((v) => options.contains(v['planCode'])),
  ];
  double monthly = 0, tax = 0, install = 0, installTax = 0;
  bool hasBase = false;
  for (var i = 0; i < records.length; i++) {
    final prices = array(
      records[i]['pricings'],
    ).map(object).where((v) => v['mode'] == 'default');
    final month = prices
        .where(
          (v) =>
              v['intervalUnit'] == 'month' &&
              v['interval'] == 1 &&
              !array(v['capacities']).contains('installation'),
        )
        .firstOrNull;
    final setup = prices
        .where((v) => array(v['capacities']).contains('installation'))
        .firstOrNull;
    if (i == 0) hasBase = month?['price'] is num;
    monthly += (month?['price'] as num? ?? 0) / 1e8;
    tax += (month?['tax'] as num? ?? 0) / 1e8;
    install += (setup?['price'] as num? ?? 0) / 1e8;
    installTax += (setup?['tax'] as num? ?? 0) / 1e8;
  }
  return hasBase
      ? PlanPrice(
          monthly,
          tax,
          install,
          installTax,
          text(object(catalog['locale'])['currencyCode']),
        )
      : null;
}
