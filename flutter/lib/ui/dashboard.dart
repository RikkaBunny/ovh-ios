import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/models.dart';
import 'common.dart';
import 'instances.dart';
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
    await Future.wait([
      store.refreshOverview(),
      store.load('/system/metrics', unknownOnFailure: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final store = PanelScope.of(context),
        stats = store.state('/stats'),
        queue = store.state('/queue'),
        metrics = store.state('/system/metrics');
    final active = array(queue.value)
        .map(object)
        .where(
          (q) =>
              ['running', 'pending'].contains(q['status']) &&
              q['accountId'] == store.selectedAccount,
        )
        .toList();
    final values = object(stats.value);
    return PageLayout(
      '仪表盘',
      child: PageList(
        storageKey: 'dashboard',
        refresh: refresh,
        children: [
          const Text(
            'OVH 服务器抢购平台状态概览',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          Row(
            children: [
              _stat('活跃队列', values['activeQueues']),
              const SizedBox(width: 10),
              _stat(
                '服务器总数',
                values['totalServers'],
                hint: '可用 ${text(values['availableServers'], '—')}',
              ),
              const SizedBox(width: 10),
              _stat('下单成功', values['purchaseSuccess']),
            ],
          ),
          ...loadingState(stats),
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.assignment_outlined, size: 21),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '活跃队列',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => pushPage(context, const QueuePage()),
                      child: const Text('查看全部 ›'),
                    ),
                  ],
                ),
                if (active.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.event_note_outlined,
                          size: 46,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          '暂无活跃任务',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: () =>
                              pushPage(context, const InventoryPage()),
                          icon: const Icon(Icons.add),
                          label: const Text('创建抢购任务'),
                        ),
                      ],
                    ),
                  ),
                ...active
                    .take(4)
                    .map(
                      (q) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(text(q['planCode'])),
                        subtitle: Text(text(q['datacenter']).toUpperCase()),
                        trailing: StatusBadge(
                          queueLabel(text(q['status'])),
                          healthy: true,
                        ),
                        onTap: () => pushPage(context, const QueuePage()),
                      ),
                    ),
              ],
            ),
          ),
          // Shared with the React dashboard: metrics of the panel host, below the queue.
          PanelCard(
            key: const Key('dashboard.resources'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.speed_outlined, size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '系统资源',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () =>
                          store.load('/system/metrics', unknownOnFailure: true),
                      icon: const Icon(Icons.refresh),
                      tooltip: '刷新系统资源',
                    ),
                  ],
                ),
                const Text(
                  '运行面板的服务器',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: ['cpu', 'memory', 'disk'].map((kind) {
                    final data = object(object(metrics.value)[kind]),
                        value = resourcePercent(object(metrics.value), kind);
                    return Expanded(
                      child: Column(
                        children: [
                          SizedBox(
                            width: 90,
                            height: 90,
                            child: CustomPaint(
                              painter: ResourcePainter(
                                value,
                                Theme.of(context).dividerColor,
                              ),
                              child: Center(
                                child: Text(
                                  value == null
                                      ? '—'
                                      : '${value.toStringAsFixed(1)}%',
                                  key: Key('resource.$kind'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 17,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            {'cpu': 'CPU', 'memory': '内存', 'disk': '存储'}[kind]!,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            kind == 'cpu'
                                ? '${text(data['cores'], '—')} 核'
                                : '${bytes(data['usedBytes'])}\n/ ${bytes(data['totalBytes'])}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                if (metrics.error != null) ...[
                  const SizedBox(height: 16),
                  const Notice('系统资源暂时无法读取，读数显示为未知。下拉刷新可重试。'),
                ],
              ],
            ),
          ),
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '当前账户实例',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                if (store.assets.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      '暂无实例',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ...store.assets
                    .take(4)
                    .map(
                      (asset) => AssetRow(
                        asset,
                        tap: () => pushPage(
                          context,
                          AssetPage(asset: asset, target: store.target),
                        ),
                      ),
                    ),
              ],
            ),
          ),
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '系统状态',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _status('API 连接', '已连接', true),
                _status(
                  '自动抢购',
                  active.isEmpty ? '暂无任务' : '运行中',
                  active.isNotEmpty,
                ),
                _status(
                  '服务器监控',
                  values['monitorRunning'] == true ? '已启用' : '待启用',
                  values['monitorRunning'] == true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, dynamic value, {String? hint}) => Expanded(
    child: PanelCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          const SizedBox(height: 10),
          Text(
            text(value, '—'),
            key: Key('stats.$label'),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          if (hint != null)
            Text(
              hint,
              style: const TextStyle(color: Color(0xff168b58), fontSize: 11),
            ),
        ],
      ),
    ),
  );
  Widget _status(String label, String state, bool healthy) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        StatusBadge(state, healthy: healthy),
      ],
    ),
  );
}

class ResourcePainter extends CustomPainter {
  final double? value;
  final Color track;
  ResourcePainter(this.value, this.track);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect.deflate(8), .75 * math.pi, 1.5 * math.pi, false, paint);
    if (value != null) {
      paint.color = value! >= 85
          ? const Color(0xffd94c4c)
          : value! >= 60
          ? const Color(0xffb77914)
          : const Color(0xff30ae78);
      canvas.drawArc(
        rect.deflate(8),
        .75 * math.pi,
        1.5 * math.pi * value! / 100,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(ResourcePainter oldDelegate) =>
      value != oldDelegate.value || track != oldDelegate.track;
}
