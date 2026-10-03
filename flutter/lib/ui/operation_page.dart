import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/models.dart';
import 'common.dart';

class OperationRow extends StatelessWidget {
  final Operation operation;
  final Target target;
  final Json seed;
  const OperationRow(
    this.operation,
    this.target, {
    super.key,
    this.seed = const {},
  });
  @override
  Widget build(BuildContext context) => FeatureRow(
    operation.title,
    key: Key('native.${operation.handler}'),
    icon: operation.read
        ? Icons.description_outlined
        : operation.danger
        ? Icons.warning_amber_outlined
        : Icons.tune,
    tap: () => pushPage(
      context,
      OperationPage(operation: operation, target: target, seed: seed),
    ),
  );
}

class OperationPage extends StatefulWidget {
  final Operation operation;
  final Target target;
  final Json seed;
  const OperationPage({
    super.key,
    required this.operation,
    required this.target,
    this.seed = const {},
  });
  @override
  State<OperationPage> createState() => _OperationPageState();
}

class _OperationPageState extends State<OperationPage> {
  Json values = {}, original = {};
  dynamic result;
  String? error;
  bool busy = false, started = false, configLoaded = false, succeeded = false;
  List<String> notices = [];
  final Map<String, List<String>> suggestions = {};
  int revision = 0;
  Timer? expiryTimer;
  Operation get op => widget.operation;
  List<FieldSpec> get fields => op.fields
      .where(
        (f) => !widget.target.bindings.containsKey(f.key) && f.key != 'confirm',
      )
      .toList();
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) initialize();
      });
    }
  }

  @override
  void dispose() {
    revision++;
    expiryTimer?.cancel();
    super.dispose();
  }

  Future<void> initialize() async {
    final store = PanelScope.of(context), connection = store.connection;
    values = {...widget.seed};
    original = {...widget.seed};
    for (final field in fields) {
      if (field.required && field.kind == 'toggle') {
        values.putIfAbsent(field.key, () => false);
      }
      if (field.key == 'account_id') {
        values.putIfAbsent(field.key, () => widget.target.account);
      }
    }
    if (connection == null) return;
    final ticket = store.session;
    if (op.path == '/settings' && !op.read ||
        op.path == '/accounts/:id' && op.method == 'PUT') {
      setState(() => busy = true);
      try {
        final path = op.path == '/settings'
            ? '/settings'
            : '/accounts/${Uri.encodeComponent(text(widget.target.bindings['id']))}';
        final response = await store.api.request(connection, path);
        if (!mounted || ticket != store.session) return;
        original = object(response.value);
        values = {...original};
        if (path.startsWith('/accounts/')) {
          for (final key in ['appKey', 'appSecret', 'consumerKey']) {
            values.remove(key);
          }
        }
        configLoaded = true;
        notices = response.notices;
      } catch (e) {
        if (mounted) error = '$e';
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }
    if (mounted) setState(() {});
    if (op.read && fields.isEmpty) await execute();
    if (widget.target.service != null) {
      final root =
          '${op.scope == 'vps' ? '/vps-control' : '/server-control'}/${Uri.encodeComponent(widget.target.service!)}';
      for (final item in [
        ('templateName', '/templates', 'templates', 'templateName'),
        ('templateId', '/templates', 'templates', 'id'),
        ('bootId', '/boot-mode', 'bootModes', 'bootId'),
        ('ip', '/ips', 'ips', 'ipAddress'),
        ('type', '/ipmi-types', 'supportedTypes', ''),
      ]) {
        if (!fields.any((f) => f.key == item.$1)) continue;
        try {
          final data = (await store.api.request(
            connection,
            root + item.$2,
            account: widget.target.account,
          )).value;
          final rows = data is List ? data : array(object(data)[item.$3]);
          if (mounted && ticket == store.session) {
            setState(
              () => suggestions[item.$1] = rows
                  .map(
                    (v) => text(
                      v is Map ? (v[item.$4] ?? v['templateId'] ?? v['id']) : v,
                    ),
                  )
                  .where((v) => v.isNotEmpty)
                  .toList(),
            );
          }
        } catch (_) {
          /* The form still permits direct input when optional suggestions fail. */
        }
      }
    }
  }

  Json get effectiveValues {
    final edited = {...values};
    if (op.fields.any((f) => f.key == 'confirm')) edited['confirm'] = true;
    if (op.path == '/settings' && !op.read) return {...original, ...edited};
    if (op.method == 'PUT' && original.isNotEmpty) {
      edited.removeWhere(
        (k, v) =>
            jsonEncode(v) == jsonEncode(original[k]) &&
            !op.fields.any((f) => f.key == k && f.location == 'path'),
      );
    }
    return edited;
  }

  Future<void> execute() async {
    if (busy) return;
    final store = PanelScope.of(context),
        ticket = ++revision,
        session = store.session;
    setState(() {
      busy = true;
      error = null;
      succeeded = false;
    });
    try {
      final response = await store.execute(op, widget.target, effectiveValues);
      if (!mounted || revision != ticket || store.session != session) return;
      setState(() {
        result = response.value;
        notices = response.notices;
        succeeded = !op.read;
      });
      if (op.path == '/app/pairing-codes') {
        expiryTimer?.cancel();
        expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      }
    } catch (e) {
      if (mounted && revision == ticket && session == store.session) {
        setState(() => error = '$e');
      }
    } finally {
      if (mounted && ticket == revision) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (op.path == '/settings' && !op.read && !configLoaded) return;
    try {
      op.resolve(effectiveValues, widget.target);
      if (op.read) {
        await execute();
        return;
      }
      final name =
          PanelScope.of(context).accounts
              .where(
                (a) =>
                    a.id == values['account_id'] || a.id == values['accountId'],
              )
              .firstOrNull
              ?.name ??
          widget.target.name;
      final confirmed = await confirmAction(
        context,
        op.title,
        op.globalTarget ??
            '$name${widget.target.service == null ? '' : '\n${widget.target.service}'}',
        danger: op.danger,
        typeTarget: op.typedConfirmation ? widget.target.service : null,
        detail: DataView(effectiveValues),
      );
      if (confirmed && mounted) await execute();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = PanelScope.of(context);
    final data = object(result), code = text(data['code']);
    final rawExpiry = data['expiresAt'];
    final expires = rawExpiry is num
        ? DateTime.fromMillisecondsSinceEpoch(rawExpiry.toInt() * 1000)
        : DateTime.tryParse(text(rawExpiry));
    return PageLayout(
      op.title,
      account: false,
      child: PageList(
        refresh: op.read ? execute : null,
        children: [
          Text(
            op.globalTarget ??
                '${widget.target.name}${widget.target.service == null ? '' : ' · ${widget.target.service}'}',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
          if (op.danger)
            Notice(
              op.path.endsWith('/install') || op.path.endsWith('/reinstall')
                  ? '重装会清空系统盘数据，请确认备份、系统模板和分区配置。'
                  : '此操作会修改或删除当前目标的数据，请核对后确认。',
            ),
          if (busy) const LinearProgressIndicator(minHeight: 2),
          if (error != null) Notice(error!),
          ...notices.map(Notice.new),
          if (fields.isNotEmpty)
            PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: fields
                    .map(
                      (field) => Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: FieldEditor(
                          key: ValueKey(
                            '${field.location}:${field.key}:$configLoaded',
                          ),
                          field: field,
                          value: values[field.key],
                          choices: _choices(field),
                          onChanged: (v) => setState(() {
                            values[field.key] = v;
                            if (field.key == 'zone') {
                              final site = store.catalog.subsidiaries
                                  .where((s) => s['code'] == v)
                                  .firstOrNull;
                              if (site != null) {
                                values['endpoint'] = site['endpoint'];
                              }
                            }
                          }),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          if (!op.read || fields.isNotEmpty)
            FilledButton(
              key: const Key('operation.submit'),
              onPressed:
                  busy || (op.path == '/settings' && !op.read && !configLoaded)
                  ? null
                  : submit,
              child: Text(op.read ? '查询' : op.title),
            ),
          if (op.path == '/settings' && !op.read && !configLoaded)
            OutlinedButton(onPressed: initialize, child: const Text('重新读取设置')),
          if (succeeded)
            const Text('✓ 请求已成功提交', style: TextStyle(color: Color(0xff168b58))),
          if (code.isNotEmpty && op.path == '/app/pairing-codes')
            PanelCard(
              child: Column(
                children: [
                  QrImageView(
                    data: '${store.connection?.address}/api/app/pair#$code',
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                  SelectableText(
                    code,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    expires == null
                        ? '配对码有效期 2 分钟'
                        : expires.isAfter(DateTime.now())
                        ? '有效期剩余 ${expires.difference(DateTime.now()).inSeconds} 秒'
                        : '配对码已过期，请重新生成',
                  ),
                ],
              ),
            ),
          if (result != null && code.isEmpty)
            ResourceResults(
              value: result,
              operation: op,
              target: widget.target,
            ),
          if (succeeded && widget.target.service != null)
            PanelCard(
              padding: EdgeInsets.zero,
              child: OperationRow(
                store.catalog.op(
                  'GET',
                  '${op.scope == 'vps' ? '/vps-control' : '/server-control'}/:service_name/tasks',
                ),
                widget.target,
              ),
            ),
        ],
      ),
    );
  }

  Map<String, String> _choices(FieldSpec field) {
    final store = PanelScope.of(context);
    if (['account_id', 'accountId', 'autoOrderAccountId'].contains(field.key)) {
      return {
        for (final account in store.accounts)
          account.id: '${account.name} · ${account.zone}',
      };
    }
    if (['zone', 'subsidiary', 'ovhSubsidiary'].contains(field.key)) {
      return {
        for (final site in store.catalog.subsidiaries.where(
          (s) =>
              field.key == 'zone' ||
              s['endpoint'] ==
                  store.accounts
                      .where((a) => a.id == widget.target.account)
                      .firstOrNull
                      ?.endpoint,
        ))
          text(site['code']): text(site['label']),
      };
    }
    return {
      for (final choice in [...field.choices, ...?suggestions[field.key]])
        choice: choice,
    };
  }
}

class FieldEditor extends StatefulWidget {
  final FieldSpec field;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final Map<String, String> choices;
  const FieldEditor({
    super.key,
    required this.field,
    this.value,
    required this.onChanged,
    this.choices = const {},
  });
  @override
  State<FieldEditor> createState() => _FieldEditorState();
}

class _FieldEditorState extends State<FieldEditor> {
  late final TextEditingController controller;
  String display(dynamic value) => widget.field.kind == 'list'
      ? array(value).map(text).join('\n')
      : text(value);
  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: display(widget.value));
  }

  @override
  void didUpdateWidget(FieldEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (jsonEncode(oldWidget.value) != jsonEncode(widget.value) &&
        controller.text != display(widget.value)) {
      controller.text = display(widget.value);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field, value = widget.value;
    final label = '${field.label}${field.required ? ' *' : ''}';
    Widget editor;
    if (field.kind == 'toggle') {
      editor = SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontSize: 14)),
        value: value == true,
        onChanged: widget.onChanged,
      );
    } else if (field.kind == 'object') {
      editor = PanelCard(
        child: Column(
          children: field.children
              .map(
                (child) => FieldEditor(
                  field: child,
                  value: object(value)[child.key],
                  onChanged: (v) =>
                      widget.onChanged({...object(value), child.key: v}),
                ),
              )
              .toList(),
        ),
      );
    } else if (field.kind == 'objects') {
      final items = array(value);
      editor = Column(
        children: [
          for (var i = 0; i < items.length; i++)
            PanelCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('$label ${i + 1}')),
                      IconButton(
                        onPressed: () {
                          final copy = [...items]..removeAt(i);
                          widget.onChanged(copy);
                        },
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                  ...field.children.map(
                    (child) => FieldEditor(
                      key: ValueKey('${child.key}:$i'),
                      field: child,
                      value: object(items[i])[child.key],
                      onChanged: (v) {
                        final copy = [...items];
                        copy[i] = {...object(copy[i]), child.key: v};
                        widget.onChanged(copy);
                      },
                    ),
                  ),
                ],
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => widget.onChanged([...items, <String, dynamic>{}]),
            icon: const Icon(Icons.add),
            label: Text('添加${field.label}'),
          ),
        ],
      );
    } else if (widget.choices.isNotEmpty) {
      editor = DropdownButtonFormField<String>(
        key: ValueKey('$label:${text(value)}'),
        initialValue: widget.choices.containsKey(text(value))
            ? text(value)
            : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: widget.choices.entries
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (v) => widget.onChanged(
          field.kind == 'number' ? num.tryParse(v ?? '') : v,
        ),
      );
    } else if (field.kind == 'date') {
      editor = Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.tryParse(text(value)) ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (date == null || !context.mounted) return;
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.now(),
                );
                if (time != null) {
                  widget.onChanged(
                    DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    ).toUtc().toIso8601String(),
                  );
                }
              },
              child: Text('$label：${value ?? '选择时间'}'),
            ),
          ),
          if (!field.required && value != null)
            IconButton(
              tooltip: '清除时间',
              onPressed: () => widget.onChanged(null),
              icon: const Icon(Icons.clear),
            ),
        ],
      );
    } else {
      editor = TextField(
        key: Key('input.${field.key}'),
        controller: controller,
        obscureText: field.kind == 'secret' || secretField(field.key),
        autocorrect: false,
        maxLines: field.kind == 'list' ? 4 : 1,
        keyboardType: field.kind == 'number'
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: field.kind == 'secret'
              ? '留空保留原值'
              : field.kind == 'list'
              ? '每项一行或用逗号分隔'
              : null,
        ),
        onChanged: (s) => widget.onChanged(
          field.kind == 'list'
              ? s
                    .split(RegExp(r'[\n,，]'))
                    .map((v) => v.trim())
                    .where((v) => v.isNotEmpty)
                    .toList()
              : field.kind == 'number'
              ? (s.isEmpty ? null : num.tryParse(s) ?? s)
              : s,
        ),
      );
    }
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: editor);
  }
}

class ResourceResults extends StatelessWidget {
  final dynamic value;
  final Operation operation;
  final Target target;
  const ResourceResults({
    super.key,
    required this.value,
    required this.operation,
    required this.target,
  });
  @override
  Widget build(BuildContext context) {
    final store = PanelScope.of(context), data = object(value);
    final rows = value is List
        ? value as List
        : [
            'tasks',
            'domains',
            'ips',
            'interventions',
            'plannedInterventions',
            'bootModes',
            'boots',
            'templates',
            'accesses',
            'options',
            'vracks',
            'pricings',
            'devices',
            'requests',
            'contactChangeRequests',
            'bills',
            'refunds',
            'emails',
            'virtualMacs',
            'interfaces',
            'splaList',
            'items',
          ].map((key) => data[key]).whereType<List>().firstOrNull;
    final remote = text(
      data['url'],
      text(
        object(data['console'])['url'],
        text(object(data['console'])['value']),
      ),
    );
    if (rows == null) {
      return PanelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DataView(value),
            if (operation.path.endsWith('/console') &&
                remote.startsWith('https://'))
              FilledButton.icon(
                onPressed: () => pushPage(context, RemoteConsolePage(remote)),
                icon: const Icon(Icons.desktop_windows_outlined),
                label: const Text('进入远程控制台'),
              ),
          ],
        ),
      );
    }
    if (rows.isEmpty) return const EmptyPanel('暂无记录');
    return Column(
      children: rows.map((row) {
        final record = object(row),
            ops = store.catalog.operations.where(
              (o) =>
                  o.id != operation.id &&
                  o.scope == operation.scope &&
                  ((o.path == operation.path && !o.read) ||
                      o.path.startsWith('${operation.path}/:') ||
                      (operation.path.endsWith('/templates') &&
                          (o.path.endsWith('/install') ||
                              o.path.endsWith('/reinstall')))),
            );
        final links = <Widget>[];
        for (final op in ops) {
          final bindings = {...target.bindings};
          var valid = true;
          const aliases = {
            'task_id': 'taskId',
            'boot_id': 'bootId',
            'intervention_id': 'id',
            'ip_block': 'ipBlock',
            'vrack': 'name',
          };
          for (final field in op.fields.where((f) => f.location == 'path')) {
            final v =
                bindings[field.key] ??
                record[field.key] ??
                record[aliases[field.key]] ??
                (row is Map ? null : row);
            if (v == null) {
              valid = false;
              break;
            }
            bindings[field.key] = v;
          }
          if (!valid) continue;
          final seed = {...record};
          if (operation.path.endsWith('/templates')) {
            seed[op.scope == 'vps' ? 'templateId' : 'templateName'] =
                record[op.scope == 'vps' ? 'id' : 'templateName'];
          }
          links.add(OperationRow(op, target.bind(bindings), seed: seed));
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [DataView(row), ...links],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class RemoteConsolePage extends StatefulWidget {
  final String url;
  const RemoteConsolePage(this.url, {super.key});
  @override
  State<RemoteConsolePage> createState() => _RemoteConsolePageState();
}

class _RemoteConsolePageState extends State<RemoteConsolePage> {
  late final WebViewController controller;
  String? error;
  @override
  void initState() {
    super.initState();
    final origin = Uri.parse(widget.url);
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (r) {
            final uri = Uri.parse(r.url);
            return uri.scheme == 'about' ||
                    (uri.scheme == 'https' &&
                        uri.host == origin.host &&
                        uri.port == origin.port)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == true && mounted) {
              setState(() => error = '远程控制台加载失败');
            }
          },
        ),
      )
      ..loadRequest(origin);
  }

  @override
  Widget build(BuildContext context) => PageLayout(
    '远程控制台',
    account: false,
    child: Column(
      children: [
        if (error != null) Notice(error!),
        Expanded(child: WebViewWidget(controller: controller)),
      ],
    ),
  );
}
