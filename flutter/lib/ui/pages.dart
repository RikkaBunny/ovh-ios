import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../core/models.dart';
import 'common.dart';
import 'inventory.dart';
import 'operation_page.dart';

String queueLabel(String status) =>
    {
      'pending': '等待库存',
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
  bool allAccounts = false, busy = false;
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
  Widget build(BuildContext context) {
    final store = PanelScope.of(context), loader = store.state('/queue');
    final rows = array(loader.value)
        .map(object)
        .where(
          (q) =>
              (allAccounts || q['accountId'] == store.selectedAccount) &&
              (status == '全部' || queueLabel(text(q['status'])) == status) &&
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
              const Expanded(child: Text('全部账户')),
              Switch(
                value: allAccounts,
                onChanged: (v) => setState(() {
                  allAccounts = v;
                  selected.clear();
                }),
              ),
            ],
          ),
          TextField(
            onChanged: (v) => setState(() => search = v),
            decoration: const InputDecoration(
              hintText: '搜索机型或机房',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['全部', '等待库存', '运行中', '已暂停', '已完成', '失败']
                  .map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(s),
                        selected: status == s,
                        onSelected: (_) => setState(() => status = s),
                        labelStyle: TextStyle(
                          color: status == s
                              ? Theme.of(context).colorScheme.onPrimary
                              : null,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          ...loadingState(loader),
          if (batchError != null) Notice(batchError!),
          if (selected.isNotEmpty)
            PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('已选择 ${selected.length} 个任务'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: ['暂停', '恢复', '删除']
                        .map(
                          (s) => OutlinedButton(
                            onPressed: busy ? null : () => batch(rows, s),
                            child: Text(s),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          if (rows.isEmpty && !loader.loading)
            EmptyPanel(
              '暂无抢购任务',
              action: FilledButton.icon(
                onPressed: () => pushPage(context, const InventoryPage()),
                icon: const Icon(Icons.add),
                label: const Text('创建抢购任务'),
              ),
            ),
          ...rows.map((q) {
            final id = text(q['id']),
                target = store.target.bind({'id': q['id']});
            final owner = store.accounts
                .where((a) => a.id == q['accountId'])
                .firstOrNull;
            return PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: selected.contains(id),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            selected.add(id);
                          } else {
                            selected.remove(id);
                          }
                        }),
                      ),
                      Expanded(
                        child: Text(
                          text(q['planCode']),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      StatusBadge(
                        queueLabel(text(q['status'])),
                        healthy: ['running', 'completed'].contains(q['status']),
                      ),
                    ],
                  ),
                  Text(
                    '${owner?.name ?? '账户不可用'} · ${text(q['datacenter']).toUpperCase()}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('详情与操作', style: TextStyle(fontSize: 13)),
                    children: [
                      DataView(q),
                      OperationRow(
                        store.catalog.op('PUT', '/queue/:id/status'),
                        target,
                        seed: {'status': q['status']},
                      ),
                      OperationRow(
                        store.catalog.op('PUT', '/queue/:id/interval'),
                        target,
                        seed: {'retryInterval': q['retryInterval'] ?? 60},
                      ),
                      OperationRow(
                        store.catalog.op('DELETE', '/queue/:id'),
                        target,
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
          PanelCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                OperationRow(
                  store.catalog.op('GET', '/queue/timings'),
                  store.target,
                ),
                OperationRow(
                  store.catalog.op('DELETE', '/queue/clear'),
                  store.target,
                ),
              ],
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

  @override
  Widget build(BuildContext context) {
    final store = PanelScope.of(context),
        subs = store.state('$root/subscriptions'),
        engine = store.state('$root/status');
    final rows =
        (subs.value is List
                ? array(subs.value)
                : array(object(subs.value)['subscriptions']))
            .map(object)
            .toList();
    return PageLayout(
      widget.vps ? 'VPS 补货' : '服务器监控',
      child: PageList(
        refresh: reload,
        storageKey: root,
        children: [
          ...loadingState(subs),
          ...loadingState(engine),
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '监控引擎',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    StatusBadge(
                      object(engine.value)['running'] == true ? '运行中' : '已停止',
                      healthy: object(engine.value)['running'] == true,
                    ),
                  ],
                ),
                OperationRow(
                  store.catalog.op('POST', '$root/start'),
                  store.target,
                ),
                OperationRow(
                  store.catalog.op('POST', '$root/stop'),
                  store.target,
                ),
                OperationRow(
                  store.catalog.op('PUT', '$root/interval'),
                  store.target,
                  seed: {
                    'interval':
                        object(engine.value)['interval'] ??
                        object(engine.value)['checkInterval'] ??
                        60,
                  },
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: () => pushPage(
              context,
              widget.vps ? const VPSModelsPage() : const InventoryPage(),
            ),
            icon: const Icon(Icons.add),
            label: const Text('添加订阅'),
          ),
          if (rows.isEmpty && !subs.loading)
            const EmptyPanel('暂无监控订阅', icon: Icons.notifications_none),
          ...rows.map((row) {
            final id = row['planCode'] ?? row['id'];
            final target = store.target.bind({
              'plan_code': id,
              'id': row['id'] ?? id,
              'subscription_id': row['id'] ?? id,
            });
            return PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    text(row['serverName'], text(row['planCode'])),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DataView(row),
                  ...store.catalog.operations
                      .where(
                        (o) =>
                            o.path.startsWith('$root/subscriptions/:') &&
                            !o.path.endsWith('/history'),
                      )
                      .map((o) => OperationRow(o, target, seed: row)),
                  ...store.catalog.operations
                      .where(
                        (o) =>
                            o.path.startsWith('$root/subscriptions/:') &&
                            o.path.endsWith('/history'),
                      )
                      .map((o) => OperationRow(o, target)),
                ],
              ),
            );
          }),
          PanelCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (!widget.vps)
                  OperationRow(
                    store.catalog.op(
                      'POST',
                      '/monitor/subscriptions/batch-add-all',
                    ),
                    store.target,
                  ),
                OperationRow(
                  store.catalog.op('DELETE', '$root/subscriptions/clear'),
                  store.target,
                ),
                if (!widget.vps)
                  OperationRow(
                    store.catalog.op('POST', '/monitor/test-notification'),
                    store.target,
                  ),
              ],
            ),
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
  Widget build(BuildContext context) => PageLayout(
    '更多',
    child: PageList(
      storageKey: 'more',
      children: [
        PanelCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              FeatureRow(
                '服务器库存',
                icon: Icons.inventory_2_outlined,
                tap: () => pushPage(context, const InventoryPage()),
              ),
              FeatureRow(
                'VPS 补货',
                icon: Icons.cloud_outlined,
                tap: () => pushPage(context, const MonitorPage(vps: true)),
              ),
              FeatureRow(
                '账户管理',
                icon: Icons.person_outline,
                tap: () => pushPage(context, const AccountPage()),
              ),
            ],
          ),
        ),
        PanelCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              FeatureRow(
                '抢购历史',
                icon: Icons.history,
                tap: () => pushPage(context, const RecordsPage()),
              ),
              FeatureRow(
                '详细日志',
                icon: Icons.article_outlined,
                tap: () => pushPage(context, const RecordsPage(logs: true)),
              ),
            ],
          ),
        ),
        PanelCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              FeatureRow(
                'API 设置',
                icon: Icons.settings_outlined,
                tap: () => pushPage(context, const SettingsPage()),
              ),
              FeatureRow(
                'App 配对',
                icon: Icons.qr_code,
                tap: () => pushPage(context, const DevicesPage()),
              ),
              FeatureRow(
                '连接与设备',
                icon: Icons.phone_iphone,
                tap: () => pushPage(context, const ConnectionPage()),
              ),
              FeatureRow(
                '全部管理功能',
                icon: Icons.apps_outlined,
                tap: () => pushPage(context, const AllOperationsPage()),
              ),
            ],
          ),
        ),
      ],
    ),
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
  String get path => widget.logs ? '/logs' : '/purchase-history';
  @override
  Future<void> reload() => PanelScope.of(context).load(path);
  @override
  Widget build(BuildContext context) {
    final store = PanelScope.of(context),
        loader = store.state(path),
        rows =
            (loader.value is List
                    ? array(loader.value)
                    : array(
                        object(loader.value)[widget.logs ? 'logs' : 'history'],
                      ))
                .map(object)
                .where(
                  (r) =>
                      pretty(r).toLowerCase().contains(search.toLowerCase()) &&
                      (level == '全部' ||
                          text(r['level']).toLowerCase() == level),
                )
                .toList();
    return PageLayout(
      widget.logs ? '详细日志' : '抢购历史',
      child: PageList(
        refresh: reload,
        children: [
          TextField(
            onChanged: (v) => setState(() => search = v),
            decoration: const InputDecoration(
              hintText: '搜索记录',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          if (widget.logs)
            Wrap(
              spacing: 8,
              children: ['全部', 'info', 'warn', 'error', 'debug']
                  .map(
                    (s) => ChoiceChip(
                      label: Text(s),
                      selected: level == s,
                      onSelected: (_) => setState(() => level = s),
                    ),
                  )
                  .toList(),
            ),
          ...loadingState(loader),
          if (rows.isEmpty && !loader.loading) const EmptyPanel('暂无记录'),
          ...rows.map(
            (r) => PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    text(
                      r[widget.logs ? 'message' : 'planCode'],
                      text(r['id']),
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    text(
                      r['createdAt'],
                      text(r['purchaseTime'], text(r['timestamp'])),
                    ),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('详情', style: TextStyle(fontSize: 13)),
                    children: [
                      DataView(r),
                      TextButton.icon(
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: pretty(redacted(r))),
                        ),
                        icon: const Icon(Icons.copy),
                        label: const Text('复制记录'),
                      ),
                      Builder(
                        builder: (shareContext) => TextButton.icon(
                          onPressed: () async {
                            final box =
                                shareContext.findRenderObject() as RenderBox;
                            await SharePlus.instance.share(
                              ShareParams(
                                text: pretty(redacted(r)),
                                sharePositionOrigin:
                                    box.localToGlobal(Offset.zero) & box.size,
                              ),
                            );
                          },
                          icon: const Icon(Icons.ios_share),
                          label: const Text('分享记录'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          PanelCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                OperationRow(
                  store.catalog.op(
                    'POST',
                    widget.logs
                        ? '/logs/flush'
                        : '/purchase-history/refresh-status',
                  ),
                  store.target,
                ),
                OperationRow(store.catalog.op('DELETE', path), store.target),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final store = PanelScope.of(context);
    const groups = ['通知通道', '缓存管理', '后端系统'];
    return PageLayout(
      'API 设置',
      child: PageList(
        refresh: store.refreshOverview,
        children: [
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FeatureRow(
                  '连接与设备',
                  tap: () => pushPage(context, const ConnectionPage()),
                ),
                ValueListenableBuilder<String>(
                  valueListenable: store.appearance,
                  builder: (context, value, _) =>
                      DropdownButtonFormField<String>(
                        key: ValueKey('appearance.$value'),
                        initialValue: value,
                        decoration: const InputDecoration(labelText: '外观'),
                        items: const [
                          DropdownMenuItem(
                            value: 'system',
                            child: Text('跟随系统'),
                          ),
                          DropdownMenuItem(value: 'light', child: Text('浅色')),
                          DropdownMenuItem(value: 'dark', child: Text('深色')),
                        ],
                        onChanged: (value) {
                          if (value != null) store.setAppearance(value);
                        },
                      ),
                ),
              ],
            ),
          ),
          const Text(
            'OVH 账户',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          ...store.accounts.map(
            (a) => PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${a.name} · ${a.zone}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  ...store.catalog.operations
                      .where((o) => o.path.startsWith('/accounts/:id'))
                      .map(
                        (o) => OperationRow(o, store.target.bind({'id': a.id})),
                      ),
                ],
              ),
            ),
          ),
          PanelCard(
            padding: EdgeInsets.zero,
            child: OperationRow(
              store.catalog.op('POST', '/accounts'),
              store.target,
            ),
          ),
          PanelCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                OperationRow(
                  store.catalog.op('POST', '/settings'),
                  store.target,
                ),
                OperationRow(
                  store.catalog.op('POST', '/verify-auth'),
                  store.target,
                ),
                FeatureRow(
                  'App 配对',
                  tap: () => pushPage(context, const DevicesPage()),
                ),
              ],
            ),
          ),
          ...groups.map(
            (g) => PanelCard(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                title: Text(g),
                children: store.catalog.operations
                    .where((o) => o.scope == 'panel' && o.group == g)
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
  Widget build(BuildContext context) {
    final store = PanelScope.of(context), connection = store.connection;
    return PageLayout(
      '连接与设备',
      account: false,
      child: PageList(
        storageKey: 'connection',
        children: [
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '当前连接',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                SelectableText(connection?.address ?? '未连接'),
                const SizedBox(height: 10),
                Text(
                  connection?.deviceToken == true
                      ? '独立设备令牌 · 已保存在系统安全存储'
                      : '访问密钥 · 已保存在系统安全存储',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (connection?.deviceId != null)
                  Text(
                    '设备编号 ${connection!.deviceId}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                const SizedBox(height: 18),
                OutlinedButton(
                  onPressed: store.refreshOverview,
                  child: const Text('刷新账户与实例'),
                ),
              ],
            ),
          ),
          const Text(
            'OVH 账户',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          ...store.accounts.map(
            (a) => PanelCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(a.name),
                subtitle: Text('${a.region} · ${a.zone}'),
                trailing: store.selectedAccount == a.id
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => store.select(a.id),
              ),
            ),
          ),
          const Text(
            '关于',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'OVH · Flutter 1.2.0（1）',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const Text(
                  '连接自建的 gokele/ovh 后端，业务页面由 Flutter 绘制。',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                TextButton(
                  onPressed: () =>
                      openHttps('https://github.com/RikkaBunny/ovh-ios'),
                  child: const Text('客户端源码'),
                ),
                TextButton(
                  onPressed: () => openHttps('https://github.com/gokele/ovh'),
                  child: const Text('开源面板'),
                ),
                TextButton(
                  onPressed: () =>
                      openHttps('https://ovh-review.hejingcheng.com/privacy'),
                  child: const Text('隐私政策'),
                ),
                TextButton(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'OVH',
                    applicationVersion: 'Flutter 1.2.0',
                  ),
                  child: const Text('开源许可'),
                ),
              ],
            ),
          ),
          OutlinedButton(
            key: const Key('connection.disconnect'),
            onPressed: () async {
              if (await confirmAction(
                context,
                '断开此设备的连接',
                '只移除本机保存的令牌；重新连接需要新的配对码。',
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
              prefixIcon: Icon(Icons.search),
            ),
          ),
          ...groups.map(
            (g) => PanelCard(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
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
