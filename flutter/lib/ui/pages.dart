import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../core/models.dart';
import 'common.dart';
import 'inventory.dart';
import 'dashboard.dart';
import 'pairing_page.dart';
import 'operation_page.dart';

String queueLabel(String status) =>
    {
      'pending': '等待中',
      'success': '下单成功',
      'running': '运行中',
      'paused': '已暂停',
      'completed': '已完成',
      'failed': '失败',
    }[status] ??
    status;
mixin ReloadPage<T extends StatefulWidget> on State<T> {
  String _identity = '';
  Future<void> reload();
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = PanelScope.of(context),
        identity =
            '${store.session}|${store.selectedAccount}|${store.mutations}';
    if (_identity != identity) {
      _identity = identity;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) reload();
      });
    }
  }
}

class QueuePage extends StatefulWidget {
  const QueuePage({super.key});
  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> with ReloadPage<QueuePage> {
  bool allAccounts = false, busy = false, selectionMode = false;
  String status = '全部', search = '';
  final Set<String> selected = {};
  String? batchError;
  @override
  Future<void> reload() => PanelScope.of(context).load('/queue');
  Future<void> batch(List<Json> rows, String action) async {
    final store = PanelScope.of(context), connection = store.connection;
    if (connection == null || busy) return;
    final targets = rows
        .where((q) => selected.contains(text(q['id'])))
        .toList();
    if (!await confirmAction(
      context,
      '$action ${targets.length} 个任务',
      targets.map((q) => '${q['planCode']} · ${q['datacenter']}').join('\n'),
      danger: action == '删除',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = true;
      batchError = null;
    });
    final errors = <String>[];
    for (final q in targets) {
      if (!identical(store.connection, connection)) break;
      final base = '/queue/${Uri.encodeComponent(text(q['id']))}';
      try {
        await store.api.request(
          connection,
          base + (action == '删除' ? '' : '/status'),
          method: action == '删除' ? 'DELETE' : 'PUT',
          body: action == '删除'
              ? null
              : {'status': action == '暂停' ? 'paused' : 'running'},
        );
        selected.remove(text(q['id']));
      } catch (e) {
        errors.add('${q['planCode']}：$e');
      }
    }
    await reload();
    if (mounted) {
      setState(() {
        busy = false;
        batchError = errors.isEmpty ? null : errors.join('\n');
      });
    }
  }

  @override
  Widget build(BuildContext c) {
    final store = PanelScope.of(c), loader = store.state('/queue');
    final rows = array(loader.value)
        .map(object)
        .where(
          (q) =>
              (allAccounts || q['accountId'] == store.selectedAccount) &&
              (status == '全部' ||
                  q['status'] ==
                      {
                        '运行中': 'running',
                        '暂停': 'paused',
                        '成功': 'success',
                        '失败': 'failed',
                      }[status]) &&
              '${q['planCode']} ${q['datacenter']}'.toLowerCase().contains(
                search.toLowerCase(),
              ),
        )
        .toList();
    return PageLayout(
      '抢购队列',
      child: PageList(
        refresh: reload,
        storageKey: 'queue',
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => pushPage(c, const InventoryPage()),
                icon: const PanelIcon(Icons.add, size: 15),
                label: const Text('创建任务'),
              ),
              const Spacer(),
              const Text('全部账户', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
              PanelSwitch(
                value: allAccounts,
                onChanged: (v) => setState(() {
                  allAccounts = v;
                  selected.clear();
                }),
              ),
            ],
          ),
          Row(
            children: [
              OutlinedButton(
                onPressed: () => setState(() {
                  selectionMode = !selectionMode;
                  if (!selectionMode) selected.clear();
                }),
                child: Text(selectionMode ? '完成选择' : '批量选择'),
              ),
              if (selectionMode) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => setState(() {
                    if (selected.length == rows.length) {
                      selected.clear();
                    } else {
                      selected.addAll(rows.map((q) => text(q['id'])));
                    }
                  }),
                  child: Text(selected.length == rows.length ? '取消全选' : '全选'),
                ),
              ],
            ],
          ),
          if (selected.isNotEmpty)
            Wrap(
              spacing: 8,
              children: ['暂停', '恢复', '删除']
                  .map(
                    (action) => OutlinedButton(
                      onPressed: busy ? null : () => batch(rows, action),
                      child: Text('$action ${selected.length} 个任务'),
                    ),
                  )
                  .toList(),
            ),
          TextField(
            onChanged: (v) => setState(() => search = v),
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(hintText: '搜索机型或机房'),
          ),
          PanelSegments(
            values: const ['全部', '运行中', '暂停', '成功', '失败'],
            selected: status,
            onChanged: (v) => setState(() => status = v),
          ),
          ...loadingState(loader),
          if (batchError != null) Notice(batchError!),
          if (rows.isEmpty && !loader.loading)
            const EmptyPanel(
              '暂无抢购任务',
              subtitle: '从服务器列表选择机型与配置后创建。',
              icon: Icons.event_note_outlined,
            ),
          for (final q in rows)
            Row(
              children: [
                if (selectionMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () => setState(() {
                        final id = text(q['id']);
                        selected.contains(id)
                            ? selected.remove(id)
                            : selected.add(id);
                      }),
                      child: PanelIcon(
                        selected.contains(text(q['id']))
                            ? Icons.check_circle_outline
                            : Icons.circle_outlined,
                        size: 21,
                      ),
                    ),
                  ),
                Expanded(
                  child: PanelCard(
                    child: InkWell(
                      onTap: () => pushPage(c, QueueDetailPage(q)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  text(q['planCode']),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              StatusBadge(
                                queueLabel(text(q['status'])),
                                healthy: q['status'] == 'running',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(
                                text(q['datacenter']).toUpperCase(),
                                style: PanelDesign.mutedText(c),
                              ),
                              const Spacer(),
                              Text(
                                '尝试 ${text(q['retryCount'], '0')} 次',
                                style: PanelDesign.mutedText(c),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            store.accounts
                                    .where((a) => a.id == q['accountId'])
                                    .firstOrNull
                                    ?.name ??
                                '账户不可用',
                            style: PanelDesign.mutedText(c, 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          PanelCard(
            padding: EdgeInsets.zero,
            child: OperationRow(
              store.catalog.op('DELETE', '/queue/clear'),
              store.target,
            ),
          ),
          PanelCard(
            padding: EdgeInsets.zero,
            child: OperationRow(
              store.catalog.op('GET', '/queue/timings'),
              store.target,
            ),
          ),
        ],
      ),
    );
  }
}

class QueueDetailPage extends StatelessWidget {
  final Json item;
  const QueueDetailPage(this.item, {super.key});
  @override
  Widget build(BuildContext c) {
    final store = PanelScope.of(c);
    final target = Target(
      text(item['accountId']),
      store.accounts
              .where((a) => a.id == item['accountId'])
              .firstOrNull
              ?.name ??
          '当前任务账户',
      bindings: {'id': item['id']},
    );
    return PageLayout(
      '抢购任务',
      account: false,
      child: PageList(
        children: [
          PanelCard(child: DataView(item)),
          PanelCard(
            padding: EdgeInsets.zero,
            child: OperationRow(
              store.catalog.op('PUT', '/queue/:id/status'),
              target,
              seed: {'status': item['status']},
            ),
          ),
          PanelCard(
            padding: EdgeInsets.zero,
            child: OperationRow(
              store.catalog.op('PUT', '/queue/:id/interval'),
              target,
              seed: {'retryInterval': item['retryInterval']},
            ),
          ),
          PanelCard(
            padding: EdgeInsets.zero,
            child: OperationRow(
              store.catalog.op('DELETE', '/queue/:id'),
              target,
            ),
          ),
        ],
      ),
    );
  }
}

class MonitorPage extends StatefulWidget {
  final bool vps;
  const MonitorPage({super.key, this.vps = false});
  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage>
    with ReloadPage<MonitorPage> {
  String get root => widget.vps ? '/vps-monitor' : '/monitor';
  @override
  Future<void> reload() async {
    final store = PanelScope.of(context);
    await Future.wait([
      store.load('$root/subscriptions'),
      store.load('$root/status'),
    ]);
  }

  String search = '';
  @override
  Widget build(BuildContext c) {
    final store = PanelScope.of(c),
        subs = store.state('$root/subscriptions'),
        engine = store.state('$root/status'),
        state = object(engine.value);
    final rows =
        (subs.value is List
                ? array(subs.value)
                : array(object(subs.value)['subscriptions']))
            .map(object)
            .where(
              (row) => text(
                row['planCode'],
              ).toLowerCase().contains(search.toLowerCase()),
            )
            .toList();
    return PageLayout(
      widget.vps ? 'VPS 补货' : '服务器监控',
      child: PageList(
        refresh: reload,
        storageKey: root,
        children: [
          if (!widget.vps)
            OutlinedButton.icon(
              onPressed: () => pushPage(c, const MonitorPage(vps: true)),
              icon: const PanelIcon(Icons.cloud_outlined, size: 16),
              label: const Row(
                children: [
                  Expanded(child: Text('VPS 补货监控')),
                  PanelIcon(Icons.chevron_right, size: 11),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  '订阅数量',
                  '${array(subs.value).length}',
                  Icons.notifications_none,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricTile(
                  '检查间隔',
                  '${text(state['check_interval'], '—')}s',
                  Icons.timer_outlined,
                ),
              ),
            ],
          ),
          PanelCard(
            padding: EdgeInsets.zero,
            child: DividedRows([
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('监控引擎', style: PanelDesign.mutedText(c)),
                    ),
                    StatusBadge(
                      state['running'] == true ? '运行中' : '未运行',
                      healthy: state['running'] == true,
                    ),
                  ],
                ),
              ),
              IgnorePointer(
                ignoring:
                    engine.loading ||
                    state['running'] == null ||
                    engine.error != null,
                child: Opacity(
                  opacity:
                      engine.loading ||
                          state['running'] == null ||
                          (engine.loading ||
                              state['running'] == null ||
                              engine.error != null)
                      ? .4
                      : 1,
                  child: OperationRow(
                    store.catalog.op(
                      'POST',
                      '$root/${state['running'] == true ? 'stop' : 'start'}',
                    ),
                    store.target,
                  ),
                ),
              ),
              OperationRow(
                store.catalog.op('PUT', '$root/interval'),
                store.target,
                seed: {'interval': state['check_interval']},
              ),
            ]),
          ),
          ...loadingState(subs),
          if (engine.error != null) Notice('监控状态：${engine.error}'),
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => pushPage(
                  c,
                  widget.vps ? const VPSModelsPage() : const InventoryPage(),
                ),
                icon: const PanelIcon(Icons.add, size: 15),
                label: const Text('添加订阅'),
              ),
              const Spacer(),
              Text('${rows.length} 个订阅', style: PanelDesign.mutedText(c)),
            ],
          ),
          TextField(
            onChanged: (v) => setState(() => search = v),
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(hintText: '搜索机型'),
          ),
          if (rows.isEmpty && !subs.loading)
            const EmptyPanel(
              '暂无监控订阅',
              subtitle: '选择机型和配置，设置通知与自动抢购。',
              icon: Icons.notifications_none,
            ),
          for (final row in rows)
            PanelCard(
              child: InkWell(
                onTap: () =>
                    pushPage(c, SubscriptionDetailPage(row, vps: widget.vps)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            text(row['serverName'], text(row['planCode'])),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        PanelIcon(
                          Icons.chevron_right,
                          size: 17,
                          color: PanelDesign.muted(c),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      text(row['planCode']),
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'Menlo',
                        color: PanelDesign.muted(c),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: object(row['lastStatus']).entries
                          .map(
                            (entry) => StatusBadge(
                              entry.key.toUpperCase(),
                              healthy: orderable(text(entry.value)),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        PanelIcon(
                          row['autoOrder'] == true
                              ? Icons.flash_on_outlined
                              : Icons.notifications_none,
                          size: 13,
                          color: PanelDesign.muted(c),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          row['autoOrder'] == true ? '自动抢购' : '仅通知',
                          style: PanelDesign.mutedText(c, 11),
                        ),
                        const Spacer(),
                        Text(
                          array(row['datacenters']).isEmpty
                              ? '全部机房'
                              : array(
                                  row['datacenters'],
                                ).map(text).join('、').toUpperCase(),
                          style: PanelDesign.mutedText(c, 11),
                        ),
                      ],
                    ),
                    if (row['retired'] == true) ...[
                      const SizedBox(height: 10),
                      const Notice('该套餐已下架，请调整订阅。'),
                    ],
                  ],
                ),
              ),
            ),
          if (!widget.vps)
            PanelCard(
              padding: EdgeInsets.zero,
              child: OperationRow(
                store.catalog.op(
                  'POST',
                  '/monitor/subscriptions/batch-add-all',
                ),
                store.target,
              ),
            ),
          PanelCard(
            padding: EdgeInsets.zero,
            child: OperationRow(
              store.catalog.op('DELETE', '$root/subscriptions/clear'),
              store.target,
            ),
          ),
        ],
      ),
    );
  }
}

class SubscriptionDetailPage extends StatelessWidget {
  final Json item;
  final bool vps;
  const SubscriptionDetailPage(this.item, {super.key, this.vps = false});
  @override
  Widget build(BuildContext c) {
    final store = PanelScope.of(c), root = vps ? '/vps-monitor' : '/monitor';
    final target = store.target.bind({
      'planCode': item['planCode'],
      'plan_code': item['planCode'],
      'subscription_id': item['id'] ?? item['planCode'],
      'id': item['id'] ?? item['planCode'],
    });
    return PageLayout(
      '监控订阅',
      account: false,
      child: PageList(
        children: [
          PanelCard(child: DataView(item)),
          for (final op in store.catalog.operations.where(
            (o) => o.path.startsWith('$root/subscriptions/:'),
          ))
            PanelCard(
              padding: EdgeInsets.zero,
              child: OperationRow(op, target, seed: item),
            ),
        ],
      ),
    );
  }
}

class VPSModelsPage extends StatefulWidget {
  const VPSModelsPage({super.key});
  @override
  State<VPSModelsPage> createState() => _VPSModelsPageState();
}

class _VPSModelsPageState extends State<VPSModelsPage>
    with ReloadPage<VPSModelsPage> {
  @override
  Future<void> reload() {
    final store = PanelScope.of(context);
    return store.load(
      '/vps-monitor/models',
      account: store.selectedAccount,
      query: {'subsidiary': store.activeAccount?.zone ?? 'IE'},
      activeScope: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = PanelScope.of(context),
        loader = store.state(
          '/vps-monitor/models',
          account: store.selectedAccount,
          query: {'subsidiary': store.activeAccount?.zone ?? 'IE'},
        ),
        rows =
            (loader.value is List
                    ? array(loader.value)
                    : array(object(loader.value)['models']))
                .map(object);
    return PageLayout(
      'VPS 机型',
      child: PageList(
        refresh: reload,
        children: [
          ...loadingState(loader),
          ...rows.map(
            (row) => PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DataView(row),
                  OperationRow(
                    store.catalog.op('POST', '/vps-monitor/subscriptions'),
                    store.target,
                    seed: {
                      'planCode': row['planCode'],
                      'ovhSubsidiary': store.activeAccount?.zone,
                      'monitorLinux': true,
                      'monitorWindows': false,
                      'notifyAvailable': true,
                      'notifyUnavailable': false,
                      'autoOrder': false,
                      'autoPay': false,
                      'autoOrderAccountId': store.selectedAccount,
                      'quantity': 1,
                    },
                  ),
                  OperationRow(
                    store.catalog.op('POST', '/vps-monitor/check/:plan_code'),
                    store.target.bind({'plan_code': row['planCode']}),
                    seed: {
                      'ovhSubsidiary': store.activeAccount?.zone,
                      'accountId': store.selectedAccount,
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MorePage extends StatelessWidget {
  const MorePage({super.key});
  @override
  Widget build(BuildContext c) => PageLayout(
    '更多',
    child: PageList(
      storageKey: 'more',
      spacing: 18,
      children: [
        _section(c, '抢购', [
          FeatureRow(
            '服务器库存',
            icon: Icons.inventory_2_outlined,
            tap: () => pushPage(c, const InventoryPage()),
          ),
        ]),
        _section(c, '账户', [
          FeatureRow(
            '账户管理',
            icon: Icons.person_outline,
            tap: () => pushPage(c, const AccountPage()),
          ),
        ]),
        _section(c, '记录', [
          FeatureRow(
            '抢购历史',
            icon: Icons.history,
            tap: () => pushPage(c, const RecordsPage()),
          ),
          FeatureRow(
            '详细日志',
            icon: Icons.article_outlined,
            tap: () => pushPage(c, const RecordsPage(logs: true)),
          ),
        ]),
        _section(c, '设置', [
          FeatureRow(
            'API 设置',
            icon: Icons.tune,
            tap: () => pushPage(c, const SettingsPage()),
          ),
          FeatureRow(
            '连接与设备',
            icon: Icons.phone_iphone,
            tap: () => pushPage(c, const ConnectionPage()),
          ),
        ]),
      ],
    ),
  );
  Widget _section(BuildContext c, String name, List<Widget> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(name, style: PanelDesign.mutedText(c)),
      const SizedBox(height: 10),
      PanelCard(padding: EdgeInsets.zero, child: DividedRows(rows)),
    ],
  );
}

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage>
    with ReloadPage<AccountPage> {
  @override
  Future<void> reload() {
    final store = PanelScope.of(context);
    return store.load(
      '/ovh/account/info',
      account: store.selectedAccount,
      activeScope: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = PanelScope.of(context),
        loader = store.state(
          '/ovh/account/info',
          account: store.selectedAccount,
        );
    return PageLayout(
      '账户管理',
      child: PageList(
        refresh: reload,
        children: [
          ...loadingState(loader),
          PanelCard(child: DataView(loader.value)),
          PanelCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: store.catalog.operations
                  .where(
                    (o) => o.group == '账户管理' && o.path != '/ovh/account/info',
                  )
                  .map((o) => OperationRow(o, store.target))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class RecordsPage extends StatefulWidget {
  final bool logs;
  const RecordsPage({super.key, this.logs = false});
  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage>
    with ReloadPage<RecordsPage> {
  String search = '', level = '全部';
  bool allAccounts = true;
  int limit = 100;
  String get path => widget.logs ? '/logs' : '/purchase-history';
  @override
  Future<void> reload() => PanelScope.of(context).load(path);
  @override
  Widget build(BuildContext c) {
    final store = PanelScope.of(c), loader = store.state(path);
    final rows =
        (loader.value is List
                ? array(loader.value)
                : array(object(loader.value)[widget.logs ? 'logs' : 'history']))
            .reversed
            .map(object)
            .where(
              (row) =>
                  pretty(row).toLowerCase().contains(search.toLowerCase()) &&
                  (level == '全部' ||
                      text(
                            row[widget.logs ? 'level' : 'status'],
                          ).toUpperCase() ==
                          level.toUpperCase()) &&
                  (widget.logs ||
                      allAccounts ||
                      row['accountId'] == store.selectedAccount),
            )
            .toList();
    return PageLayout(
      widget.logs ? '详细日志' : '抢购历史',
      child: PageList(
        maxWidth: 1000,
        refresh: reload,
        children: [
          TextField(
            onChanged: (v) => setState(() => search = v),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: widget.logs ? '搜索日志内容或来源' : '搜索机型、订单或机房',
            ),
          ),
          Row(
            children: [
              DropdownButton<String>(
                value: level,
                style: TextStyle(fontSize: 13, color: PanelDesign.primary(c)),
                underline: const SizedBox(),
                items:
                    (widget.logs
                            ? ['全部', 'INFO', 'WARNING', 'ERROR', 'DEBUG']
                            : ['全部', 'success', 'failed'])
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(
                              {'success': '成功', 'failed': '失败'}[v] ?? v,
                            ),
                          ),
                        )
                        .toList(),
                onChanged: (v) => setState(() => level = v!),
              ),
              const Spacer(),
              if (!widget.logs) ...[
                const Text('全部账户', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                PanelSwitch(
                  value: allAccounts,
                  onChanged: (v) => setState(() => allAccounts = v),
                ),
              ],
            ],
          ),
          ...loadingState(loader),
          if (rows.isEmpty && !loader.loading)
            EmptyPanel(
              widget.logs ? '暂无日志' : '暂无抢购记录',
              icon: widget.logs ? Icons.article_outlined : Icons.history,
            ),
          for (final row in rows.take(limit))
            PanelCard(
              child: InkWell(
                onTap: () =>
                    pushPage(c, RecordDetailPage(row, logs: widget.logs)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            text(row[widget.logs ? 'level' : 'planCode']),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          text(
                            row[widget.logs ? 'timestamp' : 'purchaseTime'],
                          ).substring(
                            0,
                            math.min(
                              19,
                              text(
                                row[widget.logs ? 'timestamp' : 'purchaseTime'],
                              ).length,
                            ),
                          ),
                          style: PanelDesign.mutedText(c, 10),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (widget.logs)
                      Text(
                        text(row['message']),
                        maxLines: 4,
                        style: PanelDesign.mutedText(c),
                      )
                    else ...[
                      Row(
                        children: [
                          Text(
                            text(row['datacenter']).toUpperCase(),
                            style: const TextStyle(fontSize: 12),
                          ),
                          const Spacer(),
                          StatusBadge(
                            row['status'] == 'success' ? '下单成功' : '下单失败',
                            healthy: row['status'] == 'success',
                          ),
                        ],
                      ),
                      if (row['orderStatus'] != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          '付款状态：${row['orderStatus']}',
                          style: PanelDesign.mutedText(c, 11),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          if (rows.length > limit)
            OutlinedButton(
              onPressed: () => setState(() => limit += 100),
              child: Text('加载更多（剩余 ${rows.length - limit} 条）'),
            ),
          PanelCard(
            padding: EdgeInsets.zero,
            child: OperationRow(
              store.catalog.op(
                'POST',
                widget.logs
                    ? '/logs/flush'
                    : '/purchase-history/refresh-status',
              ),
              store.target,
            ),
          ),
          PanelCard(
            padding: EdgeInsets.zero,
            child: OperationRow(store.catalog.op('DELETE', path), store.target),
          ),
        ],
      ),
    );
  }
}

class RecordDetailPage extends StatelessWidget {
  final Json item;
  final bool logs;
  const RecordDetailPage(this.item, {super.key, this.logs = false});
  @override
  Widget build(BuildContext c) => PageLayout(
    logs ? '日志详情' : '订单详情',
    account: false,
    child: PageList(
      children: [
        PanelCard(child: DataView(item)),
        Builder(
          builder: (shareContext) => OutlinedButton.icon(
            onPressed: () async {
              final box = shareContext.findRenderObject() as RenderBox;
              await SharePlus.instance.share(
                ShareParams(
                  text: pretty(redacted(item)),
                  sharePositionOrigin:
                      box.localToGlobal(Offset.zero) & box.size,
                ),
              );
            },
            icon: const PanelIcon(Icons.ios_share, size: 15),
            label: const Text('分享'),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: pretty(redacted(item)))),
          icon: const PanelIcon(Icons.copy, size: 15),
          label: const Text('复制记录'),
        ),
      ],
    ),
  );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext c) {
    final store = PanelScope.of(c);
    return PageLayout(
      'API 设置',
      child: PageList(
        spacing: 18,
        children: [
          const SectionHeading('访问与外观', '连接当前自建面板'),
          PanelCard(
            padding: EdgeInsets.zero,
            child: DividedRows([
              FeatureRow(
                '访问密码与连接',
                icon: Icons.key_outlined,
                tap: () => pushPage(c, const ConnectionPage()),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: ValueListenableBuilder<String>(
                  valueListenable: store.appearance,
                  builder: (c, value, _) => Row(
                    children: [
                      const Expanded(
                        child: Text('外观', style: TextStyle(fontSize: 13)),
                      ),
                      DropdownButton<String>(
                        key: ValueKey('appearance.$value'),
                        value: value,
                        underline: const SizedBox(),
                        isDense: true,
                        style: TextStyle(
                          fontFamily: '.SF Pro Text',
                          fontSize: 13,
                          color: PanelDesign.primary(c),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'system',
                            child: Text('跟随系统'),
                          ),
                          DropdownMenuItem(value: 'light', child: Text('浅色')),
                          DropdownMenuItem(value: 'dark', child: Text('深色')),
                        ],
                        onChanged: (v) {
                          if (v != null) store.setAppearance(v);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ]),
          ),
          const SectionHeading('OVH 账户', 'EU、CA、US 的凭据和库存分别管理'),
          for (final a in store.accounts)
            PanelCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          a.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${a.endpoint} · ${a.zone}',
                        style: PanelDesign.mutedText(c, 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (a.isDefault) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: StatusBadge('默认账户', healthy: true),
                    ),
                    const SizedBox(height: 12),
                  ],
                  DividedRows(
                    store.catalog.operations
                        .where((o) => o.path.startsWith('/accounts/:id'))
                        .map(
                          (o) => OperationRow(
                            o,
                            store.target.bind({'id': a.id}),
                            seed: o.method == 'PUT'
                                ? {
                                    'name': a.name,
                                    'endpoint': a.endpoint,
                                    'zone': a.zone,
                                  }
                                : {},
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          PanelCard(
            padding: EdgeInsets.zero,
            child: OperationRow(
              store.catalog.op('POST', '/accounts'),
              store.target,
            ),
          ),
          const SectionHeading('抢购与通知', '后端设置会与网页共用'),
          PanelCard(
            padding: EdgeInsets.zero,
            child: OperationRow(
              store.catalog.op('POST', '/settings'),
              store.target,
            ),
          ),
          for (final group in ['通知通道', 'App 配对', '缓存管理', '后端系统', 'API 设置'])
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  group,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                PanelCard(
                  padding: EdgeInsets.zero,
                  child: DividedRows(
                    store.catalog.operations
                        .where(
                          (o) =>
                              o.scope == 'panel' &&
                              o.group == group &&
                              !o.path.contains(':') &&
                              o.path != '/settings',
                        )
                        .map((o) => OperationRow(o, store.target))
                        .toList(),
                  ),
                ),
              ],
            ),
          OutlinedButton.icon(
            onPressed: () => pushPage(c, const DevicesPage()),
            icon: const PanelIcon(Icons.phone_iphone, size: 15),
            label: const Text('管理已配对设备'),
          ),
          OutlinedButton.icon(
            onPressed: () => pushPage(c, const AllOperationsPage()),
            icon: const PanelIcon(Icons.apps_outlined, size: 15),
            label: const Text('全部管理功能'),
          ),
        ],
      ),
    );
  }
}

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});
  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage>
    with ReloadPage<DevicesPage> {
  @override
  Future<void> reload() => PanelScope.of(context).load('/app/devices');
  @override
  Widget build(BuildContext context) {
    final store = PanelScope.of(context), loader = store.state('/app/devices');
    return PageLayout(
      'App 配对',
      child: PageList(
        refresh: reload,
        children: [
          const Text(
            '每台设备使用独立令牌，撤销指定设备不影响其他设备。',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          ...loadingState(loader),
          ResourceResults(
            value: loader.value,
            operation: store.catalog.op('GET', '/app/devices'),
            target: store.target,
          ),
          PanelCard(
            padding: EdgeInsets.zero,
            child: OperationRow(
              store.catalog.op('POST', '/app/pairing-codes'),
              store.target,
            ),
          ),
        ],
      ),
    );
  }
}

class ConnectionPage extends StatelessWidget {
  const ConnectionPage({super.key});
  @override
  Widget build(BuildContext c) {
    final store = PanelScope.of(c), connection = store.connection;
    return PageLayout(
      '连接与设备',
      account: false,
      child: PageList(
        storageKey: 'connection',
        spacing: 16,
        children: [
          const SectionHeading('连接', '当前使用的自建 OVH 面板'),
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('面板', style: PanelDesign.mutedText(c, 13)),
                    const Spacer(),
                    Text(
                      Uri.tryParse(connection?.address ?? '')?.host ?? '',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(),
                ),
                Row(
                  children: [
                    PanelIcon(
                      Icons.lock_outline,
                      size: 14,
                      color: PanelDesign.muted(c),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      connection?.deviceToken == true
                          ? '设备令牌已存入系统安全存储'
                          : '访问密钥已存入系统安全存储',
                      style: PanelDesign.mutedText(c),
                    ),
                  ],
                ),
                if (connection?.deviceId != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    '已配对设备 · #${connection!.deviceId}',
                    style: PanelDesign.mutedText(c),
                  ),
                ],
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: store.refreshOverview,
                  icon: const PanelIcon(Icons.refresh, size: 15),
                  label: const Text('刷新账户与实例'),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () => showModalBottomSheet<void>(
                    context: c,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => const FractionallySizedBox(
                      heightFactor: .94,
                      child: PairingPage(canDismiss: true),
                    ),
                  ),
                  icon: const PanelIcon(Icons.qr_code_scanner, size: 15),
                  label: Text(
                    connection?.deviceToken == true ? '重新配对' : '改用扫码配对',
                  ),
                ),
              ],
            ),
          ),
          SectionHeading('OVH 账户', '${store.accounts.length} 个账户'),
          PanelCard(
            padding: EdgeInsets.zero,
            child: DividedRows(
              store.accounts
                  .map(
                    (a) => InkWell(
                      onTap: () => store.select(a.id),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a.name,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${a.region == 'US'
                                        ? '美国'
                                        : a.region == 'CA'
                                        ? '加拿大'
                                        : '欧洲'} · ${a.zone}',
                                    style: PanelDesign.mutedText(c, 11),
                                  ),
                                ],
                              ),
                            ),
                            if (a.id == store.selectedAccount)
                              const PanelIcon(Icons.check, size: 13),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
              inset: 14,
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => pushPage(c, const SettingsPage()),
            icon: const PanelIcon(Icons.tune, size: 15),
            label: const Text('管理账户与通知'),
          ),
          const SectionHeading('关于', 'OVH CP · 1.3.0（14）'),
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '原生客户端，连接你部署的 gokele/ovh 后端。',
                  style: PanelDesign.mutedText(c),
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: () => openHttps('https://github.com/gokele/ovh'),
                  child: const Text('开源面板 · gokele/ovh'),
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: () =>
                      openHttps('https://ovh-review.hejingcheng.com/privacy'),
                  child: const Text('隐私政策'),
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: () =>
                      openHttps('https://ovh-review.hejingcheng.com/support'),
                  child: const Text('技术支持与客户端源码'),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(),
                ),
                TextButton(
                  onPressed: () => showLicensePage(
                    context: c,
                    applicationName: 'OVH CP',
                    applicationVersion: '1.3.0（14）',
                  ),
                  child: const Row(
                    children: [
                      Expanded(child: Text('开源许可')),
                      PanelIcon(Icons.chevron_right, size: 11),
                    ],
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            key: const Key('connection.disconnect'),
            onPressed: () async {
              if (await confirmAction(
                c,
                '断开此设备的连接',
                '本机登录凭据会移除。再次连接可扫码配对或输入面板访问密钥。设备授权可以在网页设置中单独撤销。',
              )) {
                await store.disconnect();
              }
            },
            child: const Text('断开此设备的连接'),
          ),
        ],
      ),
    );
  }
}

class AllOperationsPage extends StatefulWidget {
  const AllOperationsPage({super.key});
  @override
  State<AllOperationsPage> createState() => _AllOperationsPageState();
}

class _AllOperationsPageState extends State<AllOperationsPage> {
  String search = '';
  @override
  Widget build(BuildContext context) {
    final store = PanelScope.of(context),
        ops = store.catalog.operations
            .where(
              (o) =>
                  o.scope == 'panel' &&
                  '${o.title} ${o.group}'.contains(search),
            )
            .toList(),
        groups = ops.map((o) => o.group).toSet().toList()..sort();
    return PageLayout(
      '全部管理功能',
      child: PageList(
        children: [
          TextField(
            onChanged: (v) => setState(() => search = v),
            decoration: const InputDecoration(
              hintText: '搜索管理功能',
              prefixIcon: PanelIcon(Icons.search),
            ),
          ),
          ...groups.map(
            (g) => PanelCard(
              padding: EdgeInsets.zero,
              child: PanelDisclosure(
                title: Text(g),
                children: ops
                    .where((o) => o.group == g)
                    .map((o) => OperationRow(o, store.target))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
