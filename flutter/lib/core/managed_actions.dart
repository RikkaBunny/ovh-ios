import 'models.dart';

bool managedAction(Operation op) =>
    !op.read &&
    (op.path.endsWith('/serviceinfo/renewal') ||
        op.path.endsWith('/retraction') ||
        op.path.endsWith('/rescue') ||
        op.path.endsWith('/rescue/exit') ||
        op.path == '/ovh/account/orders/:order_id/pay');

bool? renewalSupported(Json info, String mode) {
  final modes = info['renewalModes'];
  if (modes is List) return modes.contains(mode == 'auto' ? 'automatic' : mode);
  if (mode == 'manual' && info['renewalManualUnsupported'] == true) {
    return false;
  }
  return null;
}

Json checkedPayment(
  Json info,
  Target target,
  dynamic methodId, {
  DateTime? now,
}) {
  if (info['accountId'] != target.account ||
      text(info['orderId']) != text(target.bindings['order_id'])) {
    throw const PanelException('付款信息与当前账户或订单不符，请重新读取');
  }
  if (info['status'] != 'notPaid' || info['attempted'] != false) {
    throw const PanelException('订单已处理或付款状态未能确认，请到 OVH 核对');
  }
  final amount = info['amount'];
  if (amount is! num ||
      !amount.isFinite ||
      amount < 0 ||
      text(info['currency']).isEmpty) {
    throw const PanelException('缺少可靠金额或币种，不能付款');
  }
  if (text(info['expirationDate']).isNotEmpty) {
    final expiry = DateTime.tryParse(text(info['expirationDate']));
    if (expiry == null || !expiry.isAfter(now ?? DateTime.now())) {
      throw const PanelException('订单已过期或期限无法确认');
    }
  }
  final method = array(
    info['methods'],
  ).map(object).where((m) => text(m['id']) == text(methodId)).firstOrNull;
  if (method == null) throw const PanelException('请选择该订单允许的已绑定支付方式');
  return {
    'confirm': true,
    'amount': amount,
    'currency': info['currency'],
    'paymentMethodId': method['id'],
    'paymentType': method['type'],
  };
}

bool completeRescueEmail(String value) =>
    RegExp(r'^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$').hasMatch(value.trim());
