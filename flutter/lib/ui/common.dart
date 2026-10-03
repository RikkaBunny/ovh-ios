import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/models.dart';
import '../core/store.dart';

class PanelScope extends InheritedNotifier<PanelStore> {
  const PanelScope({super.key, required PanelStore store, required super.child})
    : super(notifier: store);
  static PanelStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PanelScope>()!.notifier!;
}

ThemeData panelTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final primary = dark ? Colors.white : const Color(0xff171717);
  final background = dark ? const Color(0xff101010) : Colors.white;
  final border = dark ? const Color(0xff303030) : const Color(0xffe5e5e5);
  final scheme =
      ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
        primary: primary,
        onPrimary: dark ? Colors.black : Colors.white,
        surface: background,
        outlineVariant: border,
        secondary: const Color(0xff168b58),
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: primary,
        fontWeight: FontWeight.w700,
        fontSize: 20,
      ),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      color: background,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xff222222) : const Color(0xfff5f5f5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: scheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      indicatorColor: dark ? const Color(0xff222222) : const Color(0xfff4f4f4),
      height: 70,
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: border),
      shape: const StadiumBorder(),
      selectedColor: primary,
      showCheckmark: false,
      labelStyle: TextStyle(color: primary),
      secondaryLabelStyle: TextStyle(color: scheme.onPrimary),
    ),
    textTheme: ThemeData(
      brightness: brightness,
    ).textTheme.apply(bodyColor: primary, displayColor: primary),
  );
}

class PageLayout extends StatelessWidget {
  final String title;
  final Widget child;
  final bool account;
  final List<Widget> actions;
  const PageLayout(
    this.title, {
    super.key,
    required this.child,
    this.account = true,
    this.actions = const [],
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: [
        if (account) const AccountSelector(),
        ...actions,
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(top: false, child: child),
  );
}

class AccountSelector extends StatelessWidget {
  const AccountSelector({super.key});
  @override
  Widget build(BuildContext context) {
    final store = PanelScope.of(context), account = store.activeAccount;
    return PopupMenuButton<String>(
      key: const Key('account.selector'),
      tooltip: '切换账户',
      onSelected: (id) => store.select(id),
      itemBuilder: (_) => store.accounts
          .map(
            (a) => PopupMenuItem(
              value: a.id,
              child: Text(
                '${a.name} · ${a.zone}',
                key: Key('account.${a.region}'),
              ),
            ),
          )
          .toList(),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Theme.of(context).inputDecorationTheme.fillColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                account?.name ?? '账户',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              account?.zone ?? '',
              style: const TextStyle(color: Color(0xff199c6b), fontSize: 12),
            ),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }
}

class PanelCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const PanelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class PageList extends StatelessWidget {
  final List<Widget> children;
  final Future<void> Function()? refresh;
  final String storageKey;
  const PageList({
    super.key,
    required this.children,
    this.refresh,
    this.storageKey = '',
  });
  @override
  Widget build(BuildContext context) {
    final list = SingleChildScrollView(
      key: PageStorageKey(storageKey),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children
                .map(
                  (w) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: w,
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
    return refresh == null
        ? list
        : RefreshIndicator(onRefresh: refresh!, child: list);
  }
}

class Notice extends StatelessWidget {
  final String message;
  const Notice(this.message, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xffb77914).withValues(alpha: .07),
      border: Border.all(color: const Color(0xffb77914).withValues(alpha: .4)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          size: 18,
          color: Color(0xffb77914),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 13, color: Color(0xffb77914)),
          ),
        ),
      ],
    ),
  );
}

List<Widget> loadingState(ResourceState resource) => [
  if (resource.loading) const LinearProgressIndicator(minHeight: 2),
  if (resource.error != null) Notice(resource.error!),
  ...resource.notices.toSet().map(Notice.new),
];

class EmptyPanel extends StatelessWidget {
  final String title;
  final Widget? action;
  final IconData icon;
  const EmptyPanel(
    this.title, {
    super.key,
    this.action,
    this.icon = Icons.inbox_outlined,
  });
  @override
  Widget build(BuildContext context) => PanelCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}

class StatusBadge extends StatelessWidget {
  final String label;
  final bool healthy;
  const StatusBadge(this.label, {super.key, this.healthy = false});
  @override
  Widget build(BuildContext context) {
    final color = healthy ? const Color(0xff168b58) : const Color(0xffb77914);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: color)),
    );
  }
}

class FeatureRow extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback tap;
  final String? subtitle;
  const FeatureRow(
    this.title, {
    super.key,
    required this.tap,
    this.icon = Icons.tune,
    this.subtitle,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    leading: Icon(icon, size: 23, color: Colors.grey),
    title: Text(title, style: const TextStyle(fontSize: 15)),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, style: const TextStyle(fontSize: 12)),
    trailing: const Icon(Icons.chevron_right, size: 19),
    onTap: tap,
  );
}

void pushPage(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
Future<void> openHttps(String value) async {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const PanelException('链接无效');
  }
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw const PanelException('无法打开链接');
  }
}

class DataView extends StatelessWidget {
  final dynamic value;
  const DataView(this.value, {super.key});
  @override
  Widget build(BuildContext context) {
    final catalog = PanelScope.of(context).catalog;
    if (value == null) {
      return const Text('暂无数据', style: TextStyle(color: Colors.grey));
    }
    if (value is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if ((value as List).isEmpty) const Text('暂无记录'),
          ...(value as List).map(
            (v) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PanelCard(child: DataView(v)),
            ),
          ),
        ],
      );
    }
    if (value is Map) {
      final json = object(value);
      final keys =
          json.keys.where((k) => json[k] != null && !secretField(k)).toList()
            ..sort();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: keys.map((key) {
          final v = json[key];
          if (v is Map || v is List) {
            return ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                catalog.label(key),
                style: const TextStyle(fontSize: 13),
              ),
              children: [
                Padding(padding: const EdgeInsets.all(8), child: DataView(v)),
              ],
            );
          }
          final s = v is bool ? (v ? '是' : '否') : text(v);
          final link = s.startsWith('https://');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  flex: 2,
                  child: Text(
                    catalog.label(key),
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 3,
                  child: link
                      ? Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () async {
                              try {
                                await openHttps(s);
                              } catch (_) {}
                            },
                            child: const Text('打开链接'),
                          ),
                        )
                      : SelectableText(
                          s,
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 13),
                        ),
                ),
              ],
            ),
          );
        }).toList(),
      );
    }
    return SelectableText(text(value));
  }
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String target, {
  bool danger = false,
  String? typeTarget,
  Widget? detail,
}) async {
  var typed = '';
  return await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(target),
                  if (danger) ...[
                    const SizedBox(height: 16),
                    const Notice('此操作会修改或删除目标数据，请核对后确认。'),
                  ],
                  if (detail != null) ...[const SizedBox(height: 16), detail],
                  if (typeTarget != null) ...[
                    const SizedBox(height: 16),
                    const Text('输入完整服务名称以确认'),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('operation.confirmTarget'),
                      onChanged: (s) => update(() => typed = s),
                      decoration: InputDecoration(hintText: typeTarget),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const Key('operation.confirm'),
                onPressed: typeTarget != null && typed != typeTarget
                    ? null
                    : () => Navigator.pop(context, true),
                child: const Text('确认'),
              ),
            ],
          ),
        ),
      ) ??
      false;
}
