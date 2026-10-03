import 'models.dart';

/// Instance telemetry must identify its owner and target. Host metrics are never
/// accepted here, even if an older backend ignores the query parameters.
Json checkedInstanceMetrics(dynamic raw, String account, Asset asset) {
  final data = object(raw);
  if (data['scope'] != 'instance' ||
      data['account'] != account ||
      data['service'] != asset.service ||
      data['kind'] != (asset.vps ? 'vps' : 'dedicated')) {
    throw const PanelException('资源数据与当前账户或实例不匹配');
  }
  if (!{'available', 'unavailable'}.contains(data['status'])) {
    throw const PanelException('实例监控响应不完整');
  }
  if (data['status'] == 'available') {
    final metrics = object(data['metrics']);
    if (['cpu', 'memory', 'disk'].any((key) => metrics[key] is! Map)) {
      throw const PanelException('实例资源响应不完整');
    }
  }
  return data;
}

Json unavailableInstanceMetrics(String account, Asset asset, String reason) => {
  'scope': 'instance',
  'account': account,
  'service': asset.service,
  'kind': asset.vps ? 'vps' : 'dedicated',
  'status': 'unavailable',
  'reason': reason,
};
