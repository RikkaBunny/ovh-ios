import 'package:flutter/material.dart';
import '../core/models.dart';
import '../core/managed_actions.dart';
import 'common.dart';
import 'operation_page.dart' show FieldEditor;

class ManagedActionPage extends StatefulWidget {
  final Operation operation;
  final Target target;
  const ManagedActionPage({
    super.key,
    required this.operation,
    required this.target,
  });
  @override
  State<ManagedActionPage> createState() => _ManagedActionPageState();
}

class _ManagedActionPageState extends State<ManagedActionPage> {
  Json info = {}, values = {};
  bool started = false,
      loading = true,
      sending = false,
      confirmed = false,
      submitted = false;
  String? error, outcome;
  Operation get op => widget.operation;
  bool get payment => op.path.endsWith('/pay');
  bool get renewal => op.path.endsWith('/serviceinfo/renewal');
  bool get withdrawal => op.path.endsWith('/retraction');
  bool get enteringRescue => op.path.endsWith('/rescue');
  bool get rescue => enteringRescue || op.path.endsWith('/rescue/exit');
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => load());
    }
  }

  Future<void> load() async {
    final store = PanelScope.of(context), connection = store.connection;
    if (connection == null || sending) return;
    final session = store.session;
    setState(() {
      loading = true;
      confirmed = false;
      info = {};
      values = {};
      error = null;
    });
    try {
      final path = payment
          ? '/ovh/account/orders/${Uri.encodeComponent(text(widget.target.bindings['order_id']))}/payment'
          : '${op.scope == 'vps' ? '/vps-control' : '/server-control'}/${Uri.encodeComponent(widget.target.service!)}${renewal
                ? '/serviceinfo'
                : withdrawal
                ? '/retraction'
                : '/rescue'}';
      final result = object(
        (await store.api.request(
          connection,
          path,
          account: widget.target.account,
        )).value,
      );
      if (!mounted || store.session != session) return;
      if (result['accountId'] != null &&
          result['accountId'] != widget.target.account) {
        throw const PanelException('返回的账户与当前目标不符');
      }
      setState(() {
        info = renewal ? object(result['serviceInfo'] ?? result) : result;
        if (renewal) {
          values = {
            'mode': info['renewalType'] == false
                ? 'manual'
                : info['renewalType'] == true
                ? 'auto'
                : null,
          };
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String dateLabel(dynamic value) {
    final date = DateTime.tryParse(text(value))?.toLocal();
    if (date == null) return text(value, '未知');
    return '${date.year}/${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Json get summary {
    if (renewal) {
      return {
        '当前续费模式': info['renewalType'] == true
            ? '自动续费'
            : info['renewalType'] == false
            ? '手动续费'
            : '未知',
        '当前周期': info['renewalPeriod'] == null
            ? '未知'
            : '${info['renewalPeriod']} 个月',
        '可用续费模式': info['renewalModes'] is List
            ? array(info['renewalModes'])
                  .map(
                    (v) => v == 'automatic'
                        ? '自动续费'
                        : v == 'manual'
                        ? '手动续费'
                        : text(v),
                  )
                  .join('、')
            : '未知',
      };
    }
    if (withdrawal) {
      return {
        '订单号': info['orderId'],
        '下单时间': dateLabel(info['orderDate']),
        '撤回截止时间': dateLabel(info['retractionDate']),
        '当前可撤回': info['eligible'] == true,
      };
    }
    if (rescue) {
      return {
        '下次启动项编号': info['currentBoot'],
        '已配置救援启动': info['rescueConfigured'] ?? info['inRescue'],
      };
    }
    return {
      '订单号': info['orderId'],
      '订单金额': info['priceText'] ?? '${info['amount']} ${info['currency']}',
      '订单状态': info['status'],
      '截止时间': dateLabel(info['expirationDate']),
    };
  }

  Json payload() {
    if (payment) {
      return checkedPayment(info, widget.target, values['paymentMethodId']);
    }
    if (withdrawal) {
      final expiry = DateTime.tryParse(text(info['retractionDate']));
      if (info['eligible'] != true ||
          info['orderId'] is! num ||
          expiry == null ||
          !expiry.isAfter(DateTime.now())) {
        throw const PanelException('无法确认订单仍在撤回期限内，请重新读取');
      }
      return {'confirm': true, 'orderId': info['orderId'], 'reason': 'other'};
    }
    if (renewal) {
      if (!{'auto', 'manual'}.contains(values['mode']) ||
          renewalSupported(info, text(values['mode'])) == false) {
        throw const PanelException('该服务不支持所选续费模式');
      }
      final period = values['period'];
      if (period != null &&
          (period is! num || period <= 0 || period != period.round())) {
        throw const PanelException('续费周期必须是正整数月');
      }
      return {'mode': values['mode'], 'period': ?period};
    }
    if (info['currentBoot'] is! num) {
      throw const PanelException('无法确认启动配置，请重新读取');
    }
    if (enteringRescue &&
        values['useDefaultEmail'] != true &&
        !completeRescueEmail(text(values['email']))) {
      throw const PanelException('请填写完整邮箱或选择账户联系邮箱');
    }
    return {
      'confirm': true,
      'expectedBoot': info['currentBoot'],
      if (enteringRescue) ...values,
    };
  }

  Future<void> submit() async {
    if (loading || sending || submitted || !confirmed) return;
    final store = PanelScope.of(context), session = store.session;
    try {
      final body = payload();
      final accepted = await confirmAction(
        context,
        op.title,
        '${widget.target.name}\n${widget.target.service ?? '订单 ${widget.target.bindings['order_id']}'}',
        danger: op.danger,
        detail: DataView(body),
      );
      if (!accepted || !mounted || session != store.session) return;
      setState(() {
        sending = true;
        error = null;
      });
      // Never automatically retry payment, withdrawal or rescue after an ambiguous response.
      submitted = true;
      final response = await store.execute(op, widget.target, body);
      if (mounted && session == store.session) {
        setState(
          () => outcome = text(
            object(response.value)['message'],
            '请求已提交，请刷新状态或到 OVH 官方控制台核对。',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e${submitted ? '\n本次提交不自动重试，请先核对官方状态。' : ''}');
      }
    } finally {
      if (mounted) {
        setState(() {
          sending = false;
          confirmed = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PageLayout(
    op.title,
    account: false,
    child: PageList(
      children: [
        Text(
          '${widget.target.name} · ${widget.target.service ?? '订单 ${widget.target.bindings['order_id']}'}',
        ),
        if (loading || sending) const LinearProgressIndicator(),
        if (error != null) Notice(error!),
        if (outcome != null) Notice(outcome!),
        if (!loading && info.isNotEmpty) ...[
          PanelCard(child: DataView(summary)),
          if (withdrawal)
            const Notice(
              '撤回影响整张订单内所有产品及数据（含备份），不可恢复。退款按原支付方式处理，可能扣除已使用天数；金额与结果以 OVH 为准。',
            ),
          if (rescue)
            const Notice('这里显示的是下次启动配置，不代表当前正在运行的系统。进入或退出救援会重启服务器并中断服务。'),
          if (renewal && renewalSupported(info, text(values['mode'])) == null)
            const Notice('续费能力未知，提交时由后端再次核对；未知不代表不支持。'),
          if (!submitted)
            PanelCard(
              child: Column(
                children: [
                  if (renewal) ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey(values['mode']),
                      initialValue: values['mode'] as String?,
                      decoration: const InputDecoration(labelText: '续费模式'),
                      items: ['auto', 'manual']
                          .map(
                            (mode) => DropdownMenuItem(
                              value: mode,
                              enabled: renewalSupported(info, mode) != false,
                              child: Text(mode == 'auto' ? '自动续费' : '手动续费'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() {
                        values['mode'] = v;
                        confirmed = false;
                      }),
                    ),
                    FieldEditor(
                      field: FieldSpec({
                        'key': 'period',
                        'label': '续费周期（月，留空保留当前周期）',
                        'kind': 'number',
                      }),
                      value: values['period'],
                      onChanged: (v) => setState(() {
                        values['period'] = v;
                        confirmed = false;
                      }),
                    ),
                  ],
                  if (payment)
                    DropdownButtonFormField<String>(
                      key: const Key('payment.method'),
                      decoration: const InputDecoration(labelText: '已绑定支付方式'),
                      items: array(info['methods'])
                          .map(object)
                          .map(
                            (m) => DropdownMenuItem(
                              value: text(m['id']),
                              child: Text('${m['label']} · ${m['type']}'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() {
                        values['paymentMethodId'] = v;
                        confirmed = false;
                      }),
                    ),
                  if (enteringRescue) ...[
                    SwitchListTile(
                      title: const Text('使用账户联系邮箱'),
                      value: values['useDefaultEmail'] == true,
                      onChanged: (v) => setState(() {
                        values['useDefaultEmail'] = v;
                        confirmed = false;
                        if (v) values.remove('email');
                      }),
                    ),
                    if (values['useDefaultEmail'] != true)
                      TextField(
                        key: const Key('rescue.email'),
                        decoration: const InputDecoration(
                          labelText: '接收救援密码的完整邮箱',
                        ),
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (v) => setState(() {
                          values['email'] = v;
                          confirmed = false;
                        }),
                      ),
                    FieldEditor(
                      field: FieldSpec({
                        'key': 'sshKey',
                        'label': 'SSH 公钥（可选）',
                        'kind': 'text',
                      }),
                      onChanged: (v) => setState(() {
                        values['sshKey'] = v;
                        confirmed = false;
                      }),
                    ),
                    if (array(info['boots']).isNotEmpty)
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: '救援启动项（默认由 OVH 选择）',
                        ),
                        items: array(info['boots'])
                            .map(object)
                            .map(
                              (b) => DropdownMenuItem(
                                value: text(b['bootId']),
                                child: Text(
                                  text(b['description'], text(b['bootId'])),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() {
                          values['bootId'] = int.tryParse(v ?? '');
                          confirmed = false;
                        }),
                      ),
                  ],
                  CheckboxListTile(
                    key: const Key('managed.confirm'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      payment
                          ? '确认当前账户、订单金额及支付方式，提交会扣款'
                          : withdrawal
                          ? '我已了解整单撤回、数据丢失及退款规则'
                          : rescue
                          ? '我确认邮箱与启动配置，并同意重启服务器'
                          : '确认修改该服务的续费策略',
                    ),
                    value: confirmed,
                    onChanged: (v) => setState(() => confirmed = v == true),
                  ),
                ],
              ),
            ),
          if (!submitted)
            FilledButton(
              key: const Key('managed.submit'),
              onPressed: confirmed && !sending ? submit : null,
              child: Text(op.title),
            ),
        ],
        if (!sending)
          OutlinedButton(
            onPressed: submitted ? null : load,
            child: const Text('重新读取状态'),
          ),
        if (submitted) const Notice('请返回上一级刷新，或前往 OVH 官网核对后再决定下一步。'),
      ],
    ),
  );
}
