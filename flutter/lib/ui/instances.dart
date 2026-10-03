import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/models.dart';
import 'common.dart';
import 'operation_page.dart';

class AssetRow extends StatelessWidget {
  final Asset asset;
  final VoidCallback tap;
  const AssetRow(this.asset, {super.key, required this.tap});
  @override
  Widget build(BuildContext context) => ListTile(
    key: Key('asset.${asset.service}'),
    contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    title: Text(
      asset.name,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(asset.specification, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            asset.location,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          if (asset.raw['error'] != null) Notice(text(asset.raw['error'])),
        ],
      ),
    ),
    trailing: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        StatusBadge(asset.stateLabel, healthy: asset.healthy),
        const SizedBox(height: 4),
        const Icon(Icons.chevron_right, size: 18),
      ],
    ),
    onTap: tap,
  );
}

class InstancesPage extends StatefulWidget {
  const InstancesPage({super.key});
  @override
  State<InstancesPage> createState() => _InstancesPageState();
}

class _InstancesPageState extends State<InstancesPage> {
  String search = '', kind = '全部', identity = '';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = PanelScope.of(context),
        next = '${store.session}|${store.selectedAccount}|${store.mutations}';
    if (identity != next) {
      identity = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) store.refreshOverview(includeAccounts: false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = PanelScope.of(context),
        server = store.state(
          '/server-control/list',
          account: store.selectedAccount,
        ),
        vps = store.state('/vps-control/list', account: store.selectedAccount);
    final assets = store.assets
        .where(
          (v) =>
              (kind == '全部' || (v.vps ? 'VPS' : '独立服务器') == kind) &&
              '${v.name} ${v.service} ${v.location}'.toLowerCase().contains(
                search.toLowerCase(),
              ),
        )
        .toList();
    return PageLayout(
      '服务器实例',
      child: PageList(
        storageKey: 'instances',
        refresh: () => store.refreshOverview(),
        children: [
          const Text(
            '管理当前账户的独立服务器与 VPS',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          TextField(
            key: const Key('instances.search'),
            onChanged: (s) => setState(() => search = s),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索实例、IP 或机房',
            ),
          ),
          Wrap(
            spacing: 8,
            children: ['全部', '独立服务器', 'VPS']
                .map(
                  (s) => ChoiceChip(
                    label: Text(s),
                    selected: kind == s,
                    onSelected: (_) => setState(() => kind = s),
                    labelStyle: TextStyle(
                      color: kind == s
                          ? Theme.of(context).colorScheme.onPrimary
                          : null,
                    ),
                  ),
                )
                .toList(),
          ),
          ...loadingState(server),
          ...loadingState(vps),
          Text(
            '${assets.length} 个实例',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          if (assets.isEmpty && !server.loading && !vps.loading)
            const EmptyPanel('暂无匹配实例', icon: Icons.dns_outlined),
          ...assets.map(
            (a) => PanelCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: AssetRow(
                a,
                tap: () => pushPage(
                  context,
                  AssetPage(asset: a, target: store.target),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AssetPage extends StatefulWidget {
  final Asset asset;
  final Target target;
  const AssetPage({super.key, required this.asset, required this.target});
  @override
  State<AssetPage> createState() => _AssetPageState();
}

class _AssetPageState extends State<AssetPage> {
  String tab = '概览';
  bool started = false, hideIp = false;
  Asset get asset => widget.asset;
  Target get target =>
      Target(widget.target.account, widget.target.name, service: asset.service);
  String get root => '${asset.root}/${Uri.encodeComponent(asset.service)}';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) refresh();
      });
    }
  }

  Future<void> refresh() async {
    final store = PanelScope.of(context);
    await Future.wait([
      for (final path in [
        '/serviceinfo',
        asset.vps ? '/current-os' : '/hardware',
        '/ips',
      ])
        store.load(root + path, account: target.account),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final store = PanelScope.of(context),
        scope = asset.vps ? 'vps' : 'dedicated';
    final service = store.state('$root/serviceinfo', account: target.account),
        hardware = store.state(
          root + (asset.vps ? '/current-os' : '/hardware'),
          account: target.account,
        ),
        ips = store.state('$root/ips', account: target.account);
    final operations = store.catalog.operations
        .where((o) => o.scope == scope && o.group == tab)
        .toList();
    return PageLayout(
      asset.vps ? 'VPS 控制' : '服务器控制',
      account: false,
      child: PageList(
        refresh: refresh,
        children: [
          Text(
            target.name,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.name,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  asset.service,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    StatusBadge(asset.stateLabel, healthy: asset.healthy),
                    StatusBadge(asset.location),
                    StatusBadge(asset.specification),
                  ],
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['概览', '电源', '维护', if (asset.vps) '快照', '高级']
                  .map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: Key('detail.$t'),
                        label: Text(t),
                        selected: tab == t,
                        onSelected: (_) => setState(() => tab = t),
                        labelStyle: TextStyle(
                          color: tab == t
                              ? Theme.of(context).colorScheme.onPrimary
                              : null,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          if (tab == '概览') ...[
            ...loadingState(service),
            ...loadingState(hardware),
            ...loadingState(ips),
            PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '配置信息',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
                  ),
                  const SizedBox(height: 10),
                  DataView(
                    object(hardware.value)[asset.vps
                            ? 'currentOS'
                            : 'hardware'] ??
                        hardware.value,
                  ),
                  const Divider(),
                  DataView(
                    object(service.value)['serviceInfo'] ?? service.value,
                  ),
                ],
              ),
            ),
            PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'IP 地址',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => hideIp = !hideIp),
                        child: Text(hideIp ? '显示 IP' : '隐藏 IP'),
                      ),
                    ],
                  ),
                  if (hideIp)
                    const Text('••••••')
                  else
                    DataView(object(ips.value)['ips'] ?? ips.value),
                ],
              ),
            ),
            if (!asset.vps) TrafficPanel(target),
          ],
          if (tab == '快照')
            PanelCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: store.catalog.operations
                    .where(
                      (o) => o.scope == scope && o.path.contains('/snapshot'),
                    )
                    .map((o) => OperationRow(o, target))
                    .toList(),
              ),
            ),
          if (tab != '快照')
            PanelCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: operations
                    .map((o) => OperationRow(o, target))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class TrafficPoint {
  final DateTime time;
  final double value;
  TrafficPoint(this.time, this.value);
}

List<TrafficPoint> trafficPoints(dynamic response, String mac, bool traffic) {
  final interface = array(
    object(response)['interfaces'],
  ).map(object).where((v) => v['mac'] == mac).firstOrNull;
  final points = <TrafficPoint>[];
  for (final item in array(interface?['data']).map(object)) {
    final stamp = item['timestamp'] ?? item['date'],
        number = item['value'] is num
            ? item['value']
            : object(item['value'])['value'];
    final time = stamp is num
        ? DateTime.fromMillisecondsSinceEpoch((stamp * 1000).toInt())
        : DateTime.tryParse(text(stamp));
    if (time != null && number is num && number.isFinite) {
      points.add(
        TrafficPoint(time, traffic ? number / 1e6 : number.toDouble()),
      );
    }
  }
  points.sort((a, b) => a.time.compareTo(b.time));
  return points;
}

class TrafficPanel extends StatefulWidget {
  final Target target;
  const TrafficPanel(this.target, {super.key});
  @override
  State<TrafficPanel> createState() => _TrafficPanelState();
}

class _TrafficPanelState extends State<TrafficPanel> {
  String period = 'daily', metric = 'traffic', mac = '', direction = '全部';
  double? fraction;
  bool started = false;
  String get path =>
      '/server-control/${Uri.encodeComponent(widget.target.service!)}/mrtg';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) reload();
      });
    }
  }

  Future<void> reload() async {
    final store = PanelScope.of(context);
    await Future.wait([
      for (final dir in ['download', 'upload'])
        store.load(
          path,
          account: widget.target.account,
          query: {'period': period, 'type': '$metric:$dir'},
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final store = PanelScope.of(context),
        down = store.state(
          path,
          account: widget.target.account,
          query: {'period': period, 'type': '$metric:download'},
        ),
        up = store.state(
          path,
          account: widget.target.account,
          query: {'period': period, 'type': '$metric:upload'},
        );
    final macs = {
      ...array(
        object(down.value)['interfaces'],
      ).map((v) => text(object(v)['mac'])),
      ...array(
        object(up.value)['interfaces'],
      ).map((v) => text(object(v)['mac'])),
    }.where((v) => v.isNotEmpty).toList();
    final selectedMac = macs.contains(mac) ? mac : macs.firstOrNull ?? '';
    final downloads = trafficPoints(
          down.value,
          selectedMac,
          metric == 'traffic',
        ),
        uploads = trafficPoints(up.value, selectedMac, metric == 'traffic');
    final chosen = downloads.isNotEmpty ? downloads : uploads;
    final index = fraction == null || chosen.isEmpty
        ? null
        : (fraction! * (chosen.length - 1)).round().clamp(0, chosen.length - 1);
    String summarize(List<TrafficPoint> points) => points.isEmpty
        ? '—'
        : '当前 ${points.last.value.toStringAsFixed(2)} · 平均 ${(points.map((v) => v.value).reduce((a, b) => a + b) / points.length).toStringAsFixed(2)} · 峰值 ${points.map((v) => v.value).reduce(math.max).toStringAsFixed(2)}';
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '流量监控',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(onPressed: reload, icon: const Icon(Icons.refresh)),
            ],
          ),
          Wrap(
            spacing: 10,
            children: [
              DropdownButton<String>(
                value: period,
                items: const [
                  DropdownMenuItem(value: 'hourly', child: Text('过去 1 小时')),
                  DropdownMenuItem(value: 'daily', child: Text('过去 24 小时')),
                  DropdownMenuItem(value: 'weekly', child: Text('过去 7 天')),
                  DropdownMenuItem(value: 'monthly', child: Text('过去 1 月')),
                  DropdownMenuItem(value: 'yearly', child: Text('过去 1 年')),
                ],
                onChanged: (v) {
                  setState(() => period = v!);
                  reload();
                },
              ),
              DropdownButton<String>(
                value: metric,
                items: const [
                  DropdownMenuItem(value: 'traffic', child: Text('带宽（Mbps）')),
                  DropdownMenuItem(value: 'packets', child: Text('数据包')),
                ],
                onChanged: (v) {
                  setState(() => metric = v!);
                  reload();
                },
              ),
            ],
          ),
          if (macs.isNotEmpty)
            DropdownButton<String>(
              isExpanded: true,
              value: selectedMac,
              items: macs
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) => setState(() => mac = v!),
            ),
          Wrap(
            spacing: 8,
            children: ['全部', '下载', '上传']
                .map(
                  (s) => ChoiceChip(
                    label: Text(s),
                    selected: direction == s,
                    onSelected: (_) => setState(() => direction = s),
                  ),
                )
                .toList(),
          ),
          ...loadingState(down),
          ...loadingState(up),
          const SizedBox(height: 18),
          if (chosen.isEmpty)
            const Padding(
              padding: EdgeInsets.all(22),
              child: Text('暂无流量数据', textAlign: TextAlign.center),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                onTapDown: (d) => setState(
                  () => fraction = (d.localPosition.dx / constraints.maxWidth)
                      .clamp(0, 1),
                ),
                child: SizedBox(
                  height: 160,
                  child: CustomPaint(
                    painter: TrafficPainter(
                      direction == '上传' ? [] : downloads,
                      direction == '下载' ? [] : uploads,
                      Theme.of(context).dividerColor,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            '↓ ${summarize(downloads)}${metric == 'traffic' ? ' Mbps' : ''}',
            style: const TextStyle(fontSize: 11, color: Color(0xff168b58)),
          ),
          const SizedBox(height: 8),
          Text(
            '↑ ${summarize(uploads)}${metric == 'traffic' ? ' Mbps' : ''}',
            style: const TextStyle(fontSize: 11, color: Color(0xff5287d7)),
          ),
          if (index != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                '${chosen[index].time.toLocal()} · ${chosen[index].value.toStringAsFixed(2)}${metric == 'traffic' ? ' Mbps' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class TrafficPainter extends CustomPainter {
  final List<TrafficPoint> down, up;
  final Color grid;
  TrafficPainter(this.down, this.up, this.grid);
  @override
  void paint(Canvas canvas, Size size) {
    final all = [...down, ...up];
    if (all.isEmpty) return;
    final maxValue = math.max(1.0, all.map((v) => v.value).reduce(math.max)),
        first = all.map((v) => v.time.millisecondsSinceEpoch).reduce(math.min),
        last = all.map((v) => v.time.millisecondsSinceEpoch).reduce(math.max);
    for (var i = 0; i < 5; i++) {
      canvas.drawLine(
        Offset(0, size.height * i / 4),
        Offset(size.width, size.height * i / 4),
        Paint()
          ..color = grid
          ..strokeWidth = 1,
      );
    }
    void line(List<TrafficPoint> points, Color color) {
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final x =
                (points[i].time.millisecondsSinceEpoch - first) /
                math.max(1, last - first) *
                size.width,
            y = size.height * (1 - points[i].value / maxValue);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }

    line(down, const Color(0xff168b58));
    line(up, const Color(0xff5287d7));
  }

  @override
  bool shouldRepaint(TrafficPainter oldDelegate) => true;
}
