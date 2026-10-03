import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/models.dart';
import 'common.dart';
import 'inventory.dart';
import 'pages.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool loaded = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loaded) {
      loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) refresh();
      });
    }
  }

  Future<void> refresh() async {
    final store = PanelScope.of(context);
    await store.refreshOverview();
    await store.refreshInstanceMetrics();
  }

  @override
  Widget build(BuildContext c) {
    final store = PanelScope.of(c),
        stats = store.state('/stats'),
        queue = store.state('/queue'),
        values = object(stats.value);
    final active = array(queue.value)
        .map(object)
        .where(
          (q) =>
              ['running', 'pending'].contains(q['status']) &&
              q['accountId'] == store.selectedAccount,
        )
        .toList();
    final server = store.state(
          '/server-control/list',
          account: store.selectedAccount,
        ),
        vps = store.state('/vps-control/list', account: store.selectedAccount);
    final syncError = stats.error ?? server.error ?? vps.error;
    final busy = stats.loading || server.loading || vps.loading;
    return PageLayout(
      '仪表盘',
      child: PageList(
        storageKey: 'dashboard',
        refresh: refresh,
        children: [
          Text('OVH 服务器抢购平台状态概览', style: PanelDesign.mutedText(c)),
          if (syncError != null) Notice(syncError),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: MetricTile(
                  '活跃队列',
                  text(values['activeQueues'], '—'),
                  Icons.assignment_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricTile(
                  '服务器总数',
                  text(values['totalServers'], '—'),
                  Icons.dns_outlined,
                  footnote: '可用 ${text(values['availableServers'], '—')}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricTile(
                  '下单成功',
                  text(values['purchaseSuccess'], '—'),
                  Icons.check_circle_outline,
                  footnote: '待付款',
                ),
              ),
            ],
          ),
          PanelCard(
            key: const Key('dashboard.instances'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const PanelIcon(Icons.dns_outlined, size: 17),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        '当前账户实例',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => AppTabSelection.of(c)?.call(1),
                      child: const Text('查看实例'),
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                Text(
                  store.activeAccount?.name ?? '请选择账户',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 13),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${store.assets.where((a) => !a.vps).length} 台独立服务器 · ${store.assets.where((a) => a.vps).length} 台 VPS',
                        style: PanelDesign.mutedText(c),
                      ),
                    ),
                    StatusBadge(
                      busy
                          ? '同步中'
                          : syncError == null
                          ? '已同步'
                          : '部分失败',
                      healthy: !busy && syncError == null,
                    ),
                  ],
                ),
              ],
            ),
          ),
          PanelCard(
            key: const Key('dashboard.queue'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const PanelIcon(Icons.assignment_outlined, size: 17),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        '活跃队列',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => pushPage(c, const QueuePage()),
                      child: Text('查看全部', style: PanelDesign.mutedText(c)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (active.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      children: [
                        PanelIcon(
                          Icons.event_note_outlined,
                          size: 27,
                          color: PanelDesign.muted(c),
                        ),
                        const SizedBox(height: 11),
                        Text('暂无活跃任务', style: PanelDesign.mutedText(c, 13)),
                        const SizedBox(height: 11),
                        FilledButton.icon(
                          onPressed: () => pushPage(c, const InventoryPage()),
                          icon: const PanelIcon(Icons.add, size: 15),
                          label: const Text('创建抢购任务'),
                        ),
                      ],
                    ),
                  ),
                for (final q in active.take(4))
                  Padding(
                    padding: EdgeInsets.only(top: q == active.first ? 0 : 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                text(q['planCode']),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                text(q['datacenter']).toUpperCase(),
                                style: PanelDesign.mutedText(c, 11),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          queueLabel(text(q['status'])),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SystemResourceTiles(),
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    PanelIcon(Icons.check_circle_outline, size: 17),
                    SizedBox(width: 6),
                    Text(
                      '系统状态',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _status(
                  c,
                  'API 连接',
                  stats.value == null ? '未连接' : '已连接',
                  stats.value != null,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(),
                ),
                _status(
                  c,
                  '抢购处理器',
                  values['queueProcessorRunning'] == null
                      ? '未知'
                      : values['queueProcessorRunning'] == true
                      ? '运行中'
                      : '未运行',
                  values['queueProcessorRunning'] == true,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(),
                ),
                _status(
                  c,
                  '服务器监控',
                  values['monitorRunning'] == null
                      ? '未知'
                      : values['monitorRunning'] == true
                      ? '运行中'
                      : '待启用',
                  values['monitorRunning'] == true,
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => AppTabSelection.of(c)?.call(1),
                  icon: const PanelIcon(Icons.dns_outlined, size: 16),
                  label: const Text('我的实例'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => pushPage(c, const InventoryPage()),
                  icon: const PanelIcon(Icons.inventory_2_outlined, size: 16),
                  label: const Text('服务器库存'),
                ),
              ),
            ],
          ),
          SectionHeading(
            '账户',
            '${store.accounts.length} 个账户 · 机型、价格和库存按当前账户显示',
          ),
          PanelCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final account in store.accounts) ...[
                  InkWell(
                    onTap: () => store.select(account.id),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: PanelDesign.secondary(c),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              account.zone,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  account.name,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${account.region == 'US'
                                      ? '美国'
                                      : account.region == 'CA'
                                      ? '加拿大'
                                      : '欧洲'} · ${text(store.catalog.subsidiaries.where((v) => v['code'] == account.zone).firstOrNull?['currency'], '—')}',
                                  style: PanelDesign.mutedText(c, 11),
                                ),
                              ],
                            ),
                          ),
                          PanelIcon(
                            account.id == store.selectedAccount
                                ? Icons.check
                                : Icons.chevron_right,
                            size: 13,
                            color: PanelDesign.muted(c),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (account != store.accounts.last)
                    const Padding(
                      padding: EdgeInsets.only(left: 14),
                      child: Divider(),
                    ),
                ],
              ],
            ),
          ),
          if (stats.updated != null)
            Text(
              '最后同步 ${_time(stats.updated!)}',
              textAlign: TextAlign.center,
              style: PanelDesign.mutedText(c, 11),
            ),
        ],
      ),
    );
  }

  Widget _status(BuildContext c, String title, String value, bool healthy) =>
      Row(
        children: [
          Expanded(child: Text(title, style: PanelDesign.mutedText(c))),
          StatusBadge(value, healthy: healthy),
        ],
      );
}

String _time(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class MetricTile extends StatelessWidget {
  final String title, value;
  final IconData icon;
  final String? footnote;
  const MetricTile(
    this.title,
    this.value,
    this.icon, {
    super.key,
    this.footnote,
  });
  @override
  Widget build(BuildContext c) => PanelCard(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                style: PanelDesign.mutedText(c, 11),
              ),
            ),
            PanelIcon(icon, size: 13, color: PanelDesign.muted(c)),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          value,
          key: Key('stats.$title'),
          style: const TextStyle(
            fontFamily: '.SF Pro Rounded',
            fontSize: 26,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 9),
        Text(footnote ?? ' ', style: PanelDesign.mutedText(c, 10)),
      ],
    ),
  );
}

class SystemResourceTiles extends StatelessWidget {
  const SystemResourceTiles({super.key});
  @override
  Widget build(BuildContext c) {
    final store = PanelScope.of(c), asset = store.resourceAsset;
    final metrics = store.instanceMetrics;
    final envelope = object(metrics?.value);
    final data = envelope['status'] == 'available'
        ? object(envelope['metrics'])
        : <String, dynamic>{};
    final unknown = metrics?.error != null
        ? '读取失败'
        : envelope['status'] == 'unavailable'
        ? '尚未接入监控'
        : '读取中…';
    final listStates = [
      store.state('/server-control/list', account: store.selectedAccount),
      store.state('/vps-control/list', account: store.selectedAccount),
    ];
    return Column(
      key: const Key('dashboard.resources'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '系统资源',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              store.activeAccount?.name ?? '请选择账户',
              style: PanelDesign.mutedText(c, 11),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (asset == null)
          PanelCard(
            child: Text(
              listStates.any((state) => state.loading)
                  ? '正在获取当前账户实例…'
                  : listStates.any((state) => state.error != null)
                  ? '实例列表读取失败，请下拉重试'
                  : '当前账户暂无实例',
              style: PanelDesign.mutedText(c),
            ),
          ),
        if (asset != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: PanelDesign.secondary(c),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('resource.selector'),
                value: store.resourceAssetId(asset),
                isExpanded: true,
                icon: const PanelIcon(Icons.keyboard_arrow_down, size: 14),
                items: [
                  for (final item in store.assets)
                    DropdownMenuItem(
                      value: store.resourceAssetId(item),
                      child: Text(
                        '${item.name} · ${item.vps ? 'VPS' : '独立服务器'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) store.selectResourceAsset(id);
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final kind in ['cpu', 'memory', 'disk']) ...[
                Expanded(
                  child: ResourceTile(
                    kind,
                    data,
                    metrics?.error != null,
                    unknown: unknown,
                  ),
                ),
                if (kind != 'disk') const SizedBox(width: 8),
              ],
            ],
          ),
          if (envelope['status'] == 'unavailable')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                envelope['reason'] == 'BACKEND_UNSUPPORTED'
                    ? '当前后端尚不支持实例监控。升级并配置监控来源后显示真实读数。'
                    : '此实例尚未接入系统监控，CPU、内存和存储占用未知。',
                key: const Key('resource.unavailable'),
                style: PanelDesign.mutedText(c, 11),
              ),
            ),
          if (metrics?.updated != null && envelope['status'] == 'available')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${asset.service} · 更新于 ${_time(metrics!.updated!)}',
                key: const Key('resource.identity'),
                style: PanelDesign.mutedText(c, 11),
              ),
            ),
          if (metrics?.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '资源读取失败：${metrics!.error}',
                      style: PanelDesign.mutedText(c, 11),
                    ),
                  ),
                  TextButton(
                    onPressed: () => PanelScope.of(c).refreshInstanceMetrics(),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class ResourceTile extends StatelessWidget {
  final String kind;
  final Json data;
  final bool failed;
  final String? unknown;
  const ResourceTile(
    this.kind,
    this.data,
    this.failed, {
    super.key,
    this.unknown,
  });
  @override
  Widget build(BuildContext c) {
    final value = resourcePercent(data, kind), metric = object(data[kind]);
    final tone = value == null
        ? PanelDesign.muted(c)
        : value >= 85
        ? Colors.red
        : value >= 60
        ? PanelDesign.warning
        : PanelDesign.success;
    final detail = value == null
        ? unknown ?? (failed ? '读取失败' : '读取中…')
        : kind == 'cpu'
        ? '${text(metric['cores'])} 核心'
        : '${bytes(metric['usedBytes'])} / ${bytes(metric['totalBytes'])}';
    Widget ring(double size) => SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: ResourcePainter(value, PanelDesign.border(c), tone),
        child: Center(
          child: Text(
            value == null ? '—' : '${value.round()}%',
            key: Key('resource.$kind'),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: tone,
            ),
          ),
        ),
      ),
    );
    Widget description(bool wide) => Column(
      crossAxisAlignment: wide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          {'cpu': 'CPU', 'memory': '内存', 'disk': '存储'}[kind]!,
          style: PanelDesign.mutedText(c, 11),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            detail,
            maxLines: 1,
            style: TextStyle(
              fontSize: wide ? 14 : 12,
              fontWeight: FontWeight.w600,
              color: tone,
            ),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (_, bounds) {
        final wide = bounds.maxWidth >= 258;
        return PanelCard(
          padding: wide
              ? const EdgeInsets.symmetric(horizontal: 14, vertical: 16)
              : const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: wide
              ? Row(
                  children: [
                    Expanded(child: description(true)),
                    const SizedBox(width: 12),
                    ring(96),
                  ],
                )
              : Column(
                  children: [
                    ring(68),
                    const SizedBox(height: 6),
                    description(false),
                  ],
                ),
        );
      },
    );
  }
}

class ResourcePainter extends CustomPainter {
  final double? value;
  final Color track, tone;
  ResourcePainter(this.value, this.track, this.tone);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = track;
    final rect = (Offset.zero & size).deflate(4);
    canvas.drawArc(rect, .75 * math.pi, 1.5 * math.pi, false, paint);
    if (value != null && value! > 0) {
      paint.color = tone;
      canvas.drawArc(
        rect,
        .75 * math.pi,
        1.5 * math.pi * value! / 100,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(ResourcePainter old) =>
      value != old.value || track != old.track || tone != old.tone;
}
