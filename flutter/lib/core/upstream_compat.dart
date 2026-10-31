import 'models.dart';

// Keep the exact sort/join contract of monitor.OptionsKey in gokele/ovh.
String subscriptionOptionsKey(dynamic options) =>
    (array(options).map(text).toList()..sort()).join(',');
String subscriptionIdentity(Json item) =>
    '${text(item['planCode'])}|${subscriptionOptionsKey(item['options'])}';
bool subscriptionIsUnique(Json item, List<Json> subscriptions) =>
    subscriptions.where((s) => s['planCode'] == item['planCode']).length == 1;
bool subscriptionCanAddress(Json item, List<Json> subscriptions) =>
    subscriptionOptionsKey(item['options']).isNotEmpty ||
    subscriptionIsUnique(item, subscriptions);

List<Json> mergeStockPlans(List<Json> catalog, List<Json> stock) {
  final known = catalog.map((p) => text(p['planCode'])).toSet();
  final eco = RegExp(
    r'^[0-9]{2}(sk|sys|rise)[a-z0-9]*(-v[0-9]+)?(-[a-z]+)?$',
    caseSensitive: false,
  );
  final groups = <String, List<Json>>{};
  for (final variant in stock) {
    final code = text(variant['planCode']);
    if (!known.contains(code) && eco.hasMatch(code)) {
      (groups[code] ??= []).add(variant);
    }
  }
  return [
    for (final p in catalog)
      {
        ...p,
        if (p['prerelease'] == true)
          '_stockVariants': stock
              .where((v) => v['planCode'] == p['planCode'])
              .toList(),
      },
    for (final entry in groups.entries)
      {
        'planCode': entry.key,
        'name': text(entry.value.first['server'], entry.key),
        'prerelease': true,
        'cpu': '—',
        'bandwidth': '—',
        'memory': entry.value
            .map((v) => text(v['memory']))
            .where((v) => v.isNotEmpty)
            .toSet()
            .join(' / '),
        'storage': entry.value
            .map((v) => text(v['storage']))
            .where((v) => v.isNotEmpty)
            .toSet()
            .join(' / '),
        'defaultOptions': <Json>[],
        'availableOptions': [
          for (final group in [
            ('memory', 'memory'),
            ('systemStorage', 'system-storage'),
            ('storage', 'storage'),
          ])
            for (final value
                in entry.value
                    .map((v) => text(v[group.$1]))
                    .where((v) => v.isNotEmpty)
                    .toSet())
              {'value': value, 'label': value, 'family': group.$2},
        ],
        'datacenters': entry.value
            .expand((v) => array(v['datacenters']))
            .map(object)
            .toList(),
        '_stockVariants': entry.value,
      },
  ];
}

bool preorderConfigurationMatches(Json plan, List<String> options) {
  if (plan['prerelease'] != true || options.isEmpty) return true;
  final variants = array(plan['_stockVariants']).map(object);
  return variants.any(
    (v) => options.every(
      (o) => [
        text(v['memory']),
        text(v['storage']),
        text(v['systemStorage']),
      ].contains(o),
    ),
  );
}

String planSearchText(Json plan) => [
  for (final key in [
    'name',
    'planCode',
    'cpu',
    'memory',
    'storage',
    'description',
  ])
    text(plan[key]),
  if (plan['prerelease'] == true) '预发布 预售 预约 preorder prerelease',
].join(' ').toLowerCase();

List<Json> installationQuestionFields(dynamic questions) => [
  for (final q in array(questions).map(object))
    if (text(q['name']).isNotEmpty)
      {
        'key': text(q['name']),
        'label': text(q['description'], text(q['name'])),
        'kind': q['type'] == 'boolean'
            ? 'toggle'
            : q['name'] == 'postInstallationScript'
            ? 'multiline'
            : 'text',
        'location': 'body',
        'required': q['required'] == true,
      },
];

Json normalizedCustomizations(dynamic questions, Json answers) {
  final result = <String, dynamic>{};
  for (final q in array(questions).map(object)) {
    final name = text(q['name']);
    if (name.isEmpty) continue;
    final value = answers[name] ?? (q['type'] == 'boolean' ? false : null);
    if (q['required'] == true &&
        (value == null || value is String && value.trim().isEmpty)) {
      throw PanelException('请填写${text(q['description'], name)}');
    }
    if (value == null || value is String && value.trim().isEmpty) continue;
    if (q['type'] == 'boolean' ? value is! bool : value is! String) {
      throw PanelException('${text(q['description'], name)}类型不正确');
    }
    result[name] = value;
  }
  return result;
}

// A completed purchase must never be resumed as another purchase.
bool queueOrdered(Json row) =>
    const {'completed', 'success'}.contains(row['status']);

bool versionAtLeast(String value, int major, int minor, int patch) {
  final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:$|[-+])').firstMatch(value);
  if (match == null) return false;
  final current = [for (var i = 1; i <= 3; i++) int.parse(match[i]!)],
      minimum = [major, minor, patch];
  for (var i = 0; i < 3; i++) {
    if (current[i] != minimum[i]) return current[i] > minimum[i];
  }
  return true;
}
