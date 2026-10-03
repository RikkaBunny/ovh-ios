import 'package:flutter/material.dart';
import '../core/models.dart';
import 'common.dart';
import 'operation_page.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  String identity = '', search = '', family = '全部';
  bool onlyAvailable = false, includeApi = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = PanelScope.of(context),
        next = '${store.session}|${store.selectedAccount}|$includeApi';
    if (identity != next) {
      identity = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) reload();
      });
    }
  }

  Future<void> reload({bool force = false}) async {
    final store = PanelScope.of(context), account = store.activeAccount;
    if (account == null) return;
    await Future.wait([
      store.load(
        '/servers',
        account: account.id,
        query: {
          'showApiServers': '${includeApi || force}',
          'forceRefresh': '$force',
        },
        activeScope: true,
      ),
      store.load(
        '/catalog',
        account: account.id,
        query: {'subsidiary': account.zone, 'forceRefresh': '$force'},
        activeScope: true,
      ),
      store.load(
        '@stock/${account.region}',
        account: account.id,
        activeScope: true,
        fetch: (connection) => store.api.stock(account, connection),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final store = PanelScope.of(context), account = store.activeAccount;
    if (account == null) {
      return const PageLayout('服务器库存', child: EmptyPanel('请先添加 OVH 账户'));
    }
    final plans = store.state('/servers', account: account.id),
        catalog = store.state(
          '/catalog',
          account: account.id,
          query: {'subsidiary': account.zone},
        ),
        stock = store.state('@stock/${account.region}', account: account.id);
    final live = <String, Map<String, String>>{};
    for (final variant in array(stock.value).map(object)) {
      final plan = text(variant['planCode']);
      for (final dc in array(variant['datacenters']).map(object)) {
        final place = text(dc['datacenter']).toLowerCase(),
            status = text(dc['availability']);
        if (!orderable(live[plan]?[place] ?? '')) {
          (live[plan] ??= {})[place] = status;
        }
      }
    }
    final rows =
        (plans.value is List
                ? array(plans.value)
                : array(object(plans.value)['servers']))
            .map(object)
            .map((p) {
              final current = live[text(p['planCode'])];
              return current == null
                  ? p
                  : {
                      ...p,
                      'datacenters': current.entries
                          .map(
                            (e) => {
                              'datacenter': e.key,
                              'availability': e.value,
                            },
                          )
                          .toList(),
                    };
            })
            .where((p) {
              final content = [
                'name',
                'planCode',
                'cpu',
                'memory',
                'storage',
                'description',
              ].map((k) => text(p[k])).join(' ');
              return content.toLowerCase().contains(search.toLowerCase()) &&
                  (family == '全部' || content.toUpperCase().contains(family)) &&
                  (!onlyAvailable ||
                      array(
                        p['datacenters'],
                      ).any((d) => orderable(text(object(d)['availability']))));
            })
            .toList();
    final cache = object(object(plans.value)['cacheInfo']);
    return PageLayout(
      '服务器列表',
      child: PageList(
        maxWidth: 1100,
        storageKey: 'inventory.${account.id}',
        refresh: () => reload(force: true),
        children: [
          const Text(
            '机型、价格、库存按当前账户所在站点显示',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          TextField(
            key: const Key('inventory.search'),
            onChanged: (v) => setState(() => search = v),
            decoration: const InputDecoration(
              hintText: '搜索机型、CPU、内存或硬盘',
              prefixIcon: PanelIcon(Icons.search),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['全部', 'KS', 'SYS', 'RISE', 'ADV', 'GAME']
                  .map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: family == s
                          ? FilledButton(
                              onPressed: () => setState(() => family = s),
                              child: Text(s),
                            )
                          : OutlinedButton(
                              onPressed: () => setState(() => family = s),
                              child: Text(s),
                            ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text('仅显示有货', style: PanelDesign.mutedText(context)),
                    const Spacer(),
                    PanelSwitch(
                      value: onlyAvailable,
                      onChanged: (v) => setState(() => onlyAvailable = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Row(
                  children: [
                    Text('含 API 机型', style: PanelDesign.mutedText(context)),
                    const Spacer(),
                    PanelSwitch(
                      value: includeApi,
                      onChanged: (v) {
                        setState(() => includeApi = v);
                        reload();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          ...loadingState(plans),
          ...loadingState(catalog),
          ...loadingState(stock),
          if (cache['usingExpiredCache'] == true &&
              !plans.notices.any((n) => n.startsWith('当前展示旧目录缓存')))
            Notice(
              cacheWarning(
                'Using expired cache (${text(cache['cacheAgeMinutes'])} minutes old)',
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  stock.updated == null
                      ? '库存尚未查询'
                      : '上次库存查询 ${TimeOfDay.fromDateTime(stock.updated!).format(context)}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              TextButton(
                key: const Key('inventory.refresh'),
                onPressed: () => reload(force: true),
                child: const Text('重新拉取'),
              ),
            ],
          ),
          Text(
            '${rows.length} 个机型',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          if (rows.isEmpty && !plans.loading) const EmptyPanel('暂无匹配的机型'),
          ...rows.map(
            (p) => InkWell(
              key: Key('plan.${p['planCode']}'),
              borderRadius: BorderRadius.circular(16),
              onTap: () => pushPage(
                context,
                PlanPage(
                  plan: p,
                  target: store.target,
                  catalog: object(catalog.value),
                ),
              ),
              child: PlanCard(
                p,
                price: planPrice(
                  object(catalog.value),
                  text(p['planCode']),
                  array(
                    p['defaultOptions'],
                  ).map((v) => text(object(v)['value'])).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PlanCard extends StatelessWidget {
  final Json plan;
  final PlanPrice? price;
  const PlanCard(this.plan, {super.key, this.price});
  @override
  Widget build(BuildContext context) => PanelCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                text(plan['name'], text(plan['planCode'])),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const PanelIcon(Icons.chevron_right, size: 19),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          text(plan['planCode']),
          style: TextStyle(
            color: PanelDesign.muted(context),
            fontSize: 11,
            fontFamily: 'Menlo',
          ),
        ),
        if (text(plan['description']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              text(plan['description']),
              style: PanelDesign.mutedText(context),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          price?.label ?? '— · 当前站点暂无报价',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        ...['cpu', 'memory', 'storage', 'bandwidth']
            .where((k) => plan[k] != null)
            .map(
              (k) => Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    PanelIcon(
                      {
                        'cpu': Icons.memory,
                        'memory': Icons.developer_board_outlined,
                        'storage': Icons.storage_outlined,
                        'bandwidth': Icons.language,
                      }[k],
                      size: 14,
                      color: PanelDesign.muted(context),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        text(plan[k]),
                        style: PanelDesign.mutedText(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: array(plan['datacenters'])
              .map(object)
              .map(
                (d) => StatusBadge(
                  '${text(d['datacenter']).toUpperCase()} · ${stockLabel(text(d['availability']))}',
                  healthy: orderable(text(d['availability'])),
                ),
              )
              .toList(),
        ),
      ],
    ),
  );
}

class PlanPage extends StatefulWidget {
  final Json plan, catalog;
  final Target target;
  const PlanPage({
    super.key,
    required this.plan,
    required this.catalog,
    required this.target,
  });
  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  late List<String> options;
  String datacenter = '';
  bool quoteBusy = false;
  dynamic quote;
  String? error;
  String get stockPath =>
      '/availability/${Uri.encodeComponent(text(widget.plan['planCode']))}';
  @override
  void initState() {
    super.initState();
    options = array(
      widget.plan['defaultOptions'],
    ).map((v) => text(object(v)['value'])).toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) reload();
    });
  }

  Future<void> reload() => PanelScope.of(context).load(
    stockPath,
    account: widget.target.account,
    query: {'options': options.join(',')},
  );
  Future<void> queryPrice() async {
    if (quoteBusy) return;
    final store = PanelScope.of(context), connection = store.connection;
    if (connection == null) return;
    setState(() {
      quoteBusy = true;
      error = null;
    });
    try {
      final result = await store.api.request(
        connection,
        '/servers/${Uri.encodeComponent(text(widget.plan['planCode']))}/price',
        account: widget.target.account,
        method: 'POST',
        body: {
          'account_id': widget.target.account,
          'datacenter': datacenter,
          'options': options,
        },
      );
      if (mounted && identical(store.connection, connection)) {
        setState(() => quote = result.value);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => quoteBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = PanelScope.of(context),
        stock = store.state(
          stockPath,
          account: widget.target.account,
          query: {'options': options.join(',')},
        ),
        available = array(widget.plan['availableOptions']).map(object).toList(),
        price = planPrice(
          widget.catalog,
          text(widget.plan['planCode']),
          options,
        );
    final groups = available.map((v) => text(v['family'])).toSet();
    final dcs = array(
      widget.plan['datacenters'],
    ).map(object).map((v) => text(v['datacenter'])).toSet();
    return PageLayout(
      '机型详情',
      account: false,
      child: PageList(
        refresh: reload,
        children: [
          Text(widget.target.name, style: const TextStyle(color: Colors.grey)),
          PlanCard(widget.plan, price: price),
          if (groups.isNotEmpty)
            PanelCard(
              child: Column(
                children: groups.map((family) {
                  final items = available
                      .where((v) => v['family'] == family)
                      .toList();
                  final selected = items
                      .where((v) => options.contains(v['value']))
                      .firstOrNull;
                  return DropdownButtonFormField<String>(
                    initialValue: selected == null
                        ? null
                        : text(selected['value']),
                    isExpanded: true,
                    decoration: InputDecoration(labelText: family),
                    items: items
                        .map(
                          (v) => DropdownMenuItem(
                            value: text(v['value']),
                            child: Text(
                              text(v['label'], text(v['value'])),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (code) {
                      setState(() {
                        options.removeWhere(
                          (o) => items.any((i) => i['value'] == o),
                        );
                        if (code != null) options.add(code);
                        quote = null;
                      });
                      reload();
                    },
                  );
                }).toList(),
              ),
            ),
          ...loadingState(stock),
          if (stock.value != null) PanelCard(child: DataView(stock.value)),
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: datacenter.isEmpty ? null : datacenter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '报价数据中心'),
                  items: dcs
                      .map(
                        (dc) => DropdownMenuItem(
                          value: dc,
                          child: Text(dc.toUpperCase()),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => datacenter = v ?? ''),
                ),
                const SizedBox(height: 16),
                if (price != null) ...[
                  Text(
                    price.label,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '含税月费 ${price.money(price.monthly + price.tax)} · 安装费 ${price.money(price.installation + price.installationTax)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                ],
                OutlinedButton(
                  onPressed: quoteBusy || datacenter.isEmpty
                      ? null
                      : queryPrice,
                  child: Text(quoteBusy ? '查询中…' : '查询当前配置价格'),
                ),
                if (quote != null) DataView(quote),
                if (error != null) Notice(error!),
              ],
            ),
          ),
          FilledButton.icon(
            key: const Key('plan.order'),
            onPressed: () => pushPage(
              context,
              OrderPage(
                plan: widget.plan,
                target: widget.target,
                options: options,
              ),
            ),
            icon: const PanelIcon(Icons.add),
            label: const Text('创建抢购任务'),
          ),
          PanelCard(
            padding: EdgeInsets.zero,
            child: OperationRow(
              store.catalog.op('POST', '/monitor/subscriptions'),
              widget.target,
              seed: {
                'planCode': widget.plan['planCode'],
                'serverName': widget.plan['name'],
                'datacenters': dcs.toList(),
                'options': options,
                'notifyAvailable': true,
                'notifyUnavailable': false,
                'autoOrder': false,
                'autoPay': false,
                'quantity': 1,
                'autoOrderAccountId': widget.target.account,
              },
            ),
          ),
        ],
      ),
    );
  }
}

class OrderPage extends StatefulWidget {
  final Json plan;
  final Target target;
  final List<String> options;
  const OrderPage({
    super.key,
    required this.plan,
    required this.target,
    required this.options,
  });
  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  final Set<String> centers = {};
  int quantity = 1, interval = 60, done = 0;
  bool autoPay = false, busy = false;
  String? error;
  int get total => centers.length * quantity;
  Future<void> submit() async {
    final store = PanelScope.of(context), connection = store.connection;
    if (connection == null ||
        busy ||
        total < 1 ||
        total > 60 ||
        interval < 1 ||
        interval > 86400) {
      return;
    }
    final confirmed = await confirmAction(
      context,
      '确认创建抢购任务',
      '${widget.target.name}\n${widget.plan['planCode']}\n${centers.join('、')} · $total 个任务\n${autoPay ? '成功下单后会使用默认支付方式自动扣款' : '下单后手动付款'}',
      danger: autoPay,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      for (final dc in centers) {
        for (var i = 0; i < quantity; i++) {
          if (!identical(connection, store.connection)) {
            throw const PanelException('连接已改变，请核对已创建的任务');
          }
          await store.api.request(
            connection,
            '/queue',
            method: 'POST',
            body: {
              'account_id': widget.target.account,
              'planCode': widget.plan['planCode'],
              'datacenter': dc,
              'options': widget.options,
              'retryInterval': interval,
              'autoPay': autoPay,
            },
          );
          if (mounted) setState(() => done++);
        }
      }
      await store.refreshOverview(includeAccounts: false);
    } catch (e) {
      if (mounted) setState(() => error = '已创建 $done / $total 个任务。$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageLayout(
    '创建抢购任务',
    account: false,
    child: PageList(
      children: [
        Text(
          '下单账户：${widget.target.name}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        PlanCard(widget.plan),
        PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('数据中心', style: TextStyle(fontWeight: FontWeight.w600)),
              ...array(widget.plan['datacenters']).map(object).map((d) {
                final dc = text(d['datacenter']);
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(dc.toUpperCase()),
                  value: centers.contains(dc),
                  onChanged: busy || done > 0
                      ? null
                      : (v) => setState(() {
                          if (v == true) {
                            centers.add(dc);
                          } else {
                            centers.remove(dc);
                          }
                        }),
                );
              }),
              Row(
                children: [
                  Expanded(child: Text('每个机房 $quantity 台')),
                  IconButton(
                    onPressed: quantity > 1 && !busy && done == 0
                        ? () => setState(() => quantity--)
                        : null,
                    icon: const PanelIcon(Icons.remove),
                  ),
                  IconButton(
                    onPressed: quantity < 20 && !busy && done == 0
                        ? () => setState(() => quantity++)
                        : null,
                    icon: const PanelIcon(Icons.add),
                  ),
                ],
              ),
              TextFormField(
                initialValue: '60',
                enabled: !busy && done == 0,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '重试间隔（秒）'),
                onChanged: (v) =>
                    setState(() => interval = int.tryParse(v) ?? 0),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('下单成功后自动付款'),
                value: autoPay,
                onChanged: busy || done > 0
                    ? null
                    : (v) => setState(() => autoPay = v),
              ),
              if (autoPay) const Notice('成功下单后会使用该 OVH 账户的默认支付方式扣款。'),
              Text(
                '共 $total 个任务，每次最多 60 个任务',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        if (error != null) Notice(error!),
        if (busy || done > 0)
          Text(
            '已创建 $done / $total 个任务',
            style: const TextStyle(color: Color(0xff168b58)),
          ),
        FilledButton(
          key: const Key('order.submit'),
          onPressed:
              busy ||
                  done > 0 ||
                  total == 0 ||
                  total > 60 ||
                  interval < 1 ||
                  interval > 86400
              ? null
              : submit,
          child: Text(busy ? '创建中…' : '创建 $total 个抢购任务'),
        ),
      ],
    ),
  );
}
