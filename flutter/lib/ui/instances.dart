import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/models.dart';
import 'common.dart';
import 'operation_page.dart';

class AssetRow extends StatelessWidget {
  final Asset asset;
  final VoidCallback tap;
  const AssetRow(this.asset, {super.key, required this.tap});
  @override
  Widget build(BuildContext c) => InkWell(
    key: Key('asset.${asset.service}'),
    onTap: tap,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: PanelDesign.secondary(c),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Center(
                  child: PanelIcon(
                    asset.vps ? Icons.layers_outlined : Icons.dns_outlined,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.name,
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${asset.vps ? 'VPS' : '独立服务器'} · ${asset.location}',
                      style: PanelDesign.mutedText(c, 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 3),
              PanelIcon(
                Icons.chevron_right,
                size: 11,
                color: PanelDesign.muted(c),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            asset.specification,
            maxLines: 2,
            style: PanelDesign.mutedText(c, 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              StatusBadge(asset.stateLabel, healthy: asset.healthy),
              const Spacer(),
              Text(
                asset.raw['renewalType'] == null
                    ? '续费信息未知'
                    : asset.raw['renewalType'] == true
                    ? '自动续费'
                    : '手动续费',
                style: PanelDesign.mutedText(c, 11),
              ),
            ],
          ),
          if (asset.raw['error'] ?? asset.raw['svcInfoError']
              case final String issue)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Notice(issue),
            ),
        ],
      ),
    ),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  '管理已购独立服务器和 VPS',
                  style: PanelDesign.mutedText(context),
                ),
              ),
              OutlinedButton.icon(
                onPressed: server.loading || vps.loading
                    ? null
                    : () => store.refreshOverview(),
                icon: const PanelIcon(Icons.refresh, size: 15),
                label: const Text('刷新'),
              ),
            ],
          ),
          SizedBox(
            height: 44,
            child: TextField(
              key: const Key('instances.search'),
              onChanged: (s) => setState(() => search = s),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '搜索名称、机房或服务编号',
                prefixIcon: PanelIcon(
                  Icons.search,
                  size: 17,
                  color: PanelDesign.muted(context),
                ),
                fillColor: PanelDesign.card(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(50),
                  borderSide: BorderSide(color: PanelDesign.border(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(50),
                  borderSide: BorderSide(color: PanelDesign.border(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(50),
                  borderSide: BorderSide(color: PanelDesign.primary(context)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
          ),
          PanelSegments(
            values: const ['全部', '独立服务器', 'VPS'],
            selected: kind,
            capsule: true,
            keyPrefix: 'assets.filter.',
            onChanged: (s) => setState(() => kind = s),
          ),
          ...loadingState(server),
          ...loadingState(vps),
          if (assets.isEmpty && !server.loading && !vps.loading)
            EmptyPanel(
              search.isEmpty ? '暂无实例' : '未找到服务器',
              icon: Icons.dns_outlined,
              subtitle: search.isEmpty ? '当前账户没有返回此类型的已购实例。' : '试试其他名称或机房。',
            ),
          ...assets.map(
            (a) => PanelCard(
              padding: EdgeInsets.zero,
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
        if (!asset.vps) '/network-interfaces',
      ])
        store.load(root + path, account: target.account),
      if (tab == '快照') store.load('$root/snapshot', account: target.account),
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
        .where(
          (o) =>
              o.scope == scope &&
              (tab == '快照'
                  ? o.path.contains('/snapshot') ||
                        o.path.contains('/automated-backup')
                  : o.group == tab &&
                        !(asset.vps &&
                            tab == '高级' &&
                            (o.path.contains('/snapshot') ||
                                o.path.contains('/automated-backup')))),
        )
        .toList();
    return PageLayout(
      asset.vps ? 'VPS 控制' : '服务器控制',
      account: false,
      child: PageList(
        refresh: refresh,
        children: [
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        asset.name,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    StatusBadge(asset.stateLabel, healthy: asset.healthy),
                  ],
                ),
                const SizedBox(height: 12),
                SelectableText(
                  asset.service,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Menlo',
                    color: PanelDesign.muted(context),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        asset.specification,
                        style: PanelDesign.mutedText(context),
                      ),
                    ),
                    Text(asset.location, style: PanelDesign.mutedText(context)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(target.name, style: PanelDesign.mutedText(context)),
              ],
            ),
          ),
          PanelSegments(
            values: asset.vps
                ? const ['概览', '电源', '快照', '高级']
                : const ['概览', '电源', '维护', '高级'],
            selected: tab,
            keyPrefix: 'detail.',
            onChanged: (t) {
              setState(() => tab = t);
              if (t == '快照') {
                store.load('$root/snapshot', account: target.account);
              }
            },
          ),
          if (tab == '概览') ...[
            ...loadingState(service),
            ...loadingState(hardware),
            ...loadingState(ips),
            if (_detailRows(asset, service.value, hardware.value).isNotEmpty)
              PanelCard(
                child: Column(
                  children: [
                    for (final row in _detailRows(
                      asset,
                      service.value,
                      hardware.value,
                    )) ...[
                      Row(
                        children: [
                          Text(
                            row.$1,
                            style: PanelDesign.mutedText(context, 13),
                          ),
                          const Spacer(),
                          Flexible(
                            child: SelectableText(
                              row.$2,
                              style: const TextStyle(fontSize: 13),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                      if (row !=
                          _detailRows(
                            asset,
                            service.value,
                            hardware.value,
                          ).last)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 13),
                          child: Divider(),
                        ),
                    ],
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
                  for (final ip in _addresses(ips.value, asset))
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              hideIp ? '••••••••' : ip,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'Menlo',
                              ),
                            ),
                          ),
                          if (!hideIp)
                            IconButton(
                              tooltip: '复制 IP',
                              onPressed: () =>
                                  Clipboard.setData(ClipboardData(text: ip)),
                              icon: const PanelIcon(Icons.copy, size: 14),
                            ),
                        ],
                      ),
                    ),
                  if (_addresses(ips.value, asset).isEmpty)
                    Text('暂无 IP 信息', style: PanelDesign.mutedText(context)),
                ],
              ),
            ),
            if (!asset.vps) ...[
              ...loadingState(
                store.state(
                  '$root/network-interfaces',
                  account: target.account,
                ),
              ),
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        PanelIcon(
                          Icons.wifi,
                          size: 14,
                          color: PanelDesign.muted(context),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          '网卡接口',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (array(
                      object(
                        store
                            .state(
                              '$root/network-interfaces',
                              account: target.account,
                            )
                            .value,
                      )['interfaces'],
                    ).isEmpty)
                      Text('未发现网卡', style: PanelDesign.mutedText(context)),
                    for (final nic in array(
                      object(
                        store
                            .state(
                              '$root/network-interfaces',
                              account: target.account,
                            )
                            .value,
                      )['interfaces'],
                    ).map(object))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                hideIp ? '••••••••' : text(nic['mac']),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'Menlo',
                                ),
                              ),
                            ),
                            if (nic['_detailError'] != null)
                              const PanelIcon(
                                Icons.warning_amber_outlined,
                                size: 12,
                                color: PanelDesign.warning,
                              ),
                            Text(
                              text(nic['linkType'], '—'),
                              style: PanelDesign.mutedText(context, 11),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              TrafficPanel(target),
            ],
          ],
          if (tab == '快照') ...[
            ...loadingState(
              store.state('$root/snapshot', account: target.account),
            ),
            if (store.state('$root/snapshot', account: target.account).value !=
                null)
              PanelCard(
                child: DataView(
                  object(
                        store
                            .state('$root/snapshot', account: target.account)
                            .value,
                      )['snapshot'] ??
                      store
                          .state('$root/snapshot', account: target.account)
                          .value,
                ),
              ),
          ],
          if (tab == '高级')
            OperationGroups(operations, target)
          else if (operations.isNotEmpty)
            PanelCard(
              padding: EdgeInsets.zero,
              child: DividedRows(
                operations.map((o) => OperationRow(o, target)).toList(),
              ),
            ),
          if (tab == '概览' && !asset.vps)
            PanelCard(
              padding: EdgeInsets.zero,
              child: DividedRows([
                OperationRow(
                  store.catalog.op(
                    'PUT',
                    '/server-control/:service_name/alias',
                  ),
                  target,
                ),
                OperationRow(
                  store.catalog.op(
                    'DELETE',
                    '/server-control/:service_name/alias',
                  ),
                  target,
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

List<String> _addresses(dynamic value, Asset asset) {
  final source = object(value)['ips'] ?? value;
  final found = array(source)
      .map(
        (v) => v is String ? v : text(object(v)['ip'] ?? object(v)['address']),
      )
      .where((v) => v.isNotEmpty)
      .toList();
  if (found.isEmpty && text(asset.raw['ip']).isNotEmpty) {
    found.add(text(asset.raw['ip']));
  }
  return found;
}

String operationGroup(Operation operation) {
  final path = operation.path.split('/:service_name/').last;
  if (path.startsWith('backup-ftp')) return 'FTP 备份';
  if (path.startsWith('backup-cloud') || path.startsWith('automated-backup')) {
    return '云备份';
  }
  if (path.startsWith('secondary-dns') || path.startsWith('reverse')) {
    return 'DNS';
  }
  if (path.startsWith('ola/') ||
      path.startsWith('virtual') ||
      path.startsWith('vrack')) {
    return '虚拟网络与 vRack';
  }
  if (path.startsWith('serviceinfo') ||
      path.startsWith('engagement') ||
      path.contains('terminat') ||
      path == 'change-contact') {
    return '续费、合同与联系人';
  }
  if (path.startsWith('mitigation') || path == 'firewall' || path == 'burst') {
    return '防护与带宽';
  }
  if (path.startsWith('ip') ||
      path.startsWith('orderable') ||
      path == 'network-specs') {
    return 'IP 与网络规格';
  }
  if (path.startsWith('license') || path == 'spla' || path.startsWith('bios')) {
    return '授权与 BIOS';
  }
  return '其他服务';
}

class OperationGroups extends StatelessWidget {
  final List<Operation> operations;
  final Target target;
  const OperationGroups(this.operations, this.target, {super.key});
  @override
  Widget build(BuildContext c) {
    final groups = operations.map(operationGroup).toSet().toList()..sort();
    return Column(
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          PanelCard(
            key: ValueKey('group.${groups[i]}'),
            padding: EdgeInsets.zero,
            child: PanelDisclosure(
              title: Text(
                groups[i],
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: [
                DividedRows(
                  operations
                      .where((op) => operationGroup(op) == groups[i])
                      .map((op) => OperationRow(op, target))
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ],
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
    String formatted(double value) =>
        '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)}${metric == 'traffic' ? ' Mbps' : ''}';
    Widget summary(String title, List<TrafficPoint> points) {
      if (points.isEmpty) return const SizedBox.shrink();
      final values = [
        points.last.value,
        points.map((v) => v.value).reduce((a, b) => a + b) / points.length,
        points.map((v) => v.value).reduce(math.max),
      ];
      return Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: PanelDesign.secondary(context),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PanelIcon(
                  title == '下载' ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ['当前', '平均', '峰值'][i],
                          style: PanelDesign.mutedText(context, 11),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatted(values[i]),
                          style: const TextStyle(
                            fontSize: 11,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const PanelIcon(Icons.show_chart, size: 14),
              const SizedBox(width: 6),
              const Text(
                '流量监控',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: period,
                    isDense: true,
                    style: Theme.of(context).textTheme.bodyMedium,
                    items: const [
                      DropdownMenuItem(value: 'hourly', child: Text('过去 1 小时')),
                      DropdownMenuItem(value: 'daily', child: Text('过去 24 小时')),
                      DropdownMenuItem(value: 'weekly', child: Text('过去 7 天')),
                      DropdownMenuItem(value: 'monthly', child: Text('过去 1 月')),
                      DropdownMenuItem(value: 'yearly', child: Text('过去 1 年')),
                    ],
                    onChanged: (v) {
                      setState(() {
                        period = v!;
                        fraction = null;
                      });
                      reload();
                    },
                  ),
                ),
              ),
              IconButton(
                onPressed: reload,
                icon: const PanelIcon(Icons.refresh, size: 14),
              ),
            ],
          ),
          const SizedBox(height: 14),
          PanelSegments(
            values: const ['带宽', '数据包', '错误'],
            selected: {
              'traffic': '带宽',
              'packets': '数据包',
              'errors': '错误',
            }[metric]!,
            onChanged: (v) {
              setState(() {
                metric = {
                  '带宽': 'traffic',
                  '数据包': 'packets',
                  '错误': 'errors',
                }[v]!;
                fraction = null;
              });
              reload();
            },
          ),
          if (macs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  isDense: true,
                  value: selectedMac,
                  style: Theme.of(context).textTheme.bodyMedium,
                  items: macs
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    mac = v!;
                    fraction = null;
                  }),
                ),
              ),
            ),
          ...loadingState(down),
          ...loadingState(up),
          if (chosen.isEmpty && !down.loading)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text('当前网卡暂无数据', style: PanelDesign.mutedText(context)),
            )
          else ...[
            summary('下载', downloads),
            summary('上传', uploads),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                onTapDown: (d) => setState(
                  () => fraction =
                      (d.localPosition.dx / (constraints.maxWidth - 36)).clamp(
                        0,
                        1,
                      ),
                ),
                onHorizontalDragUpdate: (d) => setState(
                  () => fraction =
                      (d.localPosition.dx / (constraints.maxWidth - 36)).clamp(
                        0,
                        1,
                      ),
                ),
                child: SizedBox(
                  key: const Key('traffic.chart'),
                  height: 180,
                  child: CustomPaint(
                    painter: TrafficPainter(
                      direction == '上传' ? [] : downloads,
                      direction == '下载' ? [] : uploads,
                      PanelDesign.border(context),
                      PanelDesign.primary(context),
                      PanelDesign.muted(context),
                      fraction,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final label in ['下载', '上传'])
                  Padding(
                    padding: const EdgeInsets.only(right: 18),
                    child: GestureDetector(
                      onTap: () => setState(
                        () => direction = direction == label ? '全部' : label,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 3,
                            color: label == '下载'
                                ? PanelDesign.success
                                : PanelDesign.primary(context),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            label,
                            style: PanelDesign.mutedText(context, 11),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            if (index != null) ...[
              const SizedBox(height: 10),
              Text(
                '${chosen[index].time.toLocal()}'.substring(0, 16),
                style: PanelDesign.mutedText(context, 11),
              ),
              Row(
                children: [
                  for (final pair in [('下载', downloads), ('上传', uploads)])
                    if (pair.$2.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Text(
                          '${pair.$1} ${formatted(pair.$2.reduce((a, b) => a.time.difference(chosen[index].time).abs() < b.time.difference(chosen[index].time).abs() ? a : b).value)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  metric == 'traffic' ? 'Mbps' : '数据点数值',
                  style: PanelDesign.mutedText(context, 11),
                ),
                const Spacer(),
                Text(
                  '${downloads.length + uploads.length} 个数据点',
                  style: PanelDesign.mutedText(context, 11),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class TrafficPainter extends CustomPainter {
  final List<TrafficPoint> down, up;
  final Color grid, primary, muted;
  final double? fraction;
  TrafficPainter(
    this.down,
    this.up,
    this.grid,
    this.primary,
    this.muted,
    this.fraction,
  );
  @override
  void paint(Canvas canvas, Size size) {
    final all = [...down, ...up];
    if (all.isEmpty) return;
    final plot = Size(
      math.max(1, size.width - 36),
      math.max(1, size.height - 20),
    );
    final maxValue = math.max(1.0, all.map((v) => v.value).reduce(math.max)),
        first = all.map((v) => v.time.millisecondsSinceEpoch).reduce(math.min),
        last = all.map((v) => v.time.millisecondsSinceEpoch).reduce(math.max);
    void label(String value, Offset offset) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontSize: 10,
            color: muted,
            fontFamily: '.SF Pro Text',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, offset);
    }

    for (var i = 0; i < 5; i++) {
      final y = plot.height * i / 4;
      canvas.drawLine(
        Offset(0, y),
        Offset(plot.width, y),
        Paint()
          ..color = grid
          ..strokeWidth = .5,
      );
      final number = maxValue * (1 - i / 4);
      label(
        number.toStringAsFixed(number == number.roundToDouble() ? 0 : 1),
        Offset(plot.width + 7, y - 5),
      );
    }
    for (var i = 0; i < 4; i++) {
      final time = DateTime.fromMillisecondsSinceEpoch(
        first + ((last - first) * i / 3).round(),
      ).toLocal();
      label(
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
        Offset((plot.width - 30) * i / 3, plot.height + 6),
      );
    }
    void line(List<TrafficPoint> points, Color color) {
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final x =
                (points[i].time.millisecondsSinceEpoch - first) /
                math.max(1, last - first) *
                plot.width,
            y = plot.height * (1 - points[i].value / maxValue);
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

    line(down, PanelDesign.success);
    line(up, primary);
    if (fraction != null) {
      canvas.drawLine(
        Offset(plot.width * fraction!, 0),
        Offset(plot.width * fraction!, plot.height),
        Paint()
          ..color = muted.withValues(alpha: .4)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(TrafficPainter oldDelegate) => true;
}

List<(String, String)> _detailRows(
  Asset asset,
  dynamic service,
  dynamic hardware,
) {
  final info = object(object(service)['serviceInfo']),
      hw = object(object(hardware)['hardware']),
      os = object(object(hardware)['currentOS']);
  return [
    if (!asset.vps && asset.raw['os'] != null) ('操作系统', text(asset.raw['os'])),
    if (info['expiration'] != null)
      ('到期时间', text(info['expiration']).split('T').first),
    if (info['renewalType'] != null)
      (
        '自动续费',
        info['renewalType'] is bool
            ? (info['renewalType'] == true ? '是' : '否')
            : text(info['renewalType']),
      ),
    if (info['renewalPeriod'] != null)
      ('续费周期', '${text(info['renewalPeriod'])} 个月'),
    if (asset.vps && os['name'] != null) ('操作系统', text(os['name'])),
    if (hw['processorName'] != null)
      (
        '处理器',
        '${text(hw['processorName'])}${hw['coresPerProcessor'] != null && hw['threadsPerProcessor'] != null ? ' (${text(hw['coresPerProcessor'])}核/${text(hw['threadsPerProcessor'])}线程)' : ''}',
      ),
    if (array(hw['diskGroups']).isNotEmpty)
      (
        '磁盘',
        array(hw['diskGroups'])
            .map(object)
            .map(
              (d) =>
                  '${text(d['numberOfDisks'], '1')} × ${text(d['diskType'])} ${text(object(d['diskSize'])['value'])} ${text(object(d['diskSize'])['unit'])}'
                      .trim(),
            )
            .join(' / '),
      ),
    if (object(hw['memorySize'])['value'] != null)
      (
        '内存',
        '${text(object(hw['memorySize'])['value'])} ${text(object(hw['memorySize'])['unit'], 'MB')}',
      ),
  ];
}
