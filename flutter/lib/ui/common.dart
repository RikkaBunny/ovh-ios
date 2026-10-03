import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:url_launcher/url_launcher.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'design.dart';
export 'design.dart';

class PanelScope extends InheritedNotifier<PanelStore> {
  const PanelScope({super.key, required PanelStore store, required super.child})
    : super(notifier: store);
  static PanelStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PanelScope>()!.notifier!;
}

ThemeData panelTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final primary = dark ? const Color(0xfff5f5f5) : const Color(0xff171717);
  final background = dark ? const Color(0xff0f0f0f) : Colors.white;
  final card = dark ? const Color(0xff141414) : Colors.white;
  final border = dark ? const Color(0xff2e2e2e) : const Color(0xffe6e6e6);
  final muted = dark ? const Color(0xff999999) : const Color(0xff737373);
  final secondary = dark ? const Color(0xff242424) : const Color(0xfff5f5f5);
  final onPrimary = dark ? const Color(0xff171717) : const Color(0xfffafafa);
  final scheme =
      ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
        primary: primary,
        onPrimary: onPrimary,
        surface: background,
        onSurface: primary,
        onSurfaceVariant: muted,
        outline: border,
        outlineVariant: border,
        secondary: PanelDesign.success,
      );
  final text = ThemeData(brightness: brightness).textTheme.apply(
    fontFamily: '.SF Pro Text',
    bodyColor: primary,
    displayColor: primary,
  );
  final button = ButtonStyle(
    textStyle: const WidgetStatePropertyAll(
      TextStyle(
        fontFamily: '.SF Pro Text',
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
    minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 15)),
    shape: const WidgetStatePropertyAll(StadiumBorder()),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.standard,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: '.SF Pro Text',
    scaffoldBackgroundColor: background,
    textTheme: text.copyWith(
      bodyMedium: TextStyle(
        fontFamily: '.SF Pro Text',
        fontSize: 13,
        color: primary,
      ),
      bodyLarge: TextStyle(
        fontFamily: '.SF Pro Text',
        fontSize: 14,
        color: primary,
      ),
    ),
    iconTheme: IconThemeData(color: primary, size: 17),
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 52,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: '.SF Pro Text',
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
    ),
    dividerColor: border,
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: secondary,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.all(12),
      hintStyle: TextStyle(fontSize: 13, color: muted),
      labelStyle: TextStyle(fontSize: 12, color: muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: button.copyWith(
        backgroundColor: WidgetStatePropertyAll(primary),
        foregroundColor: WidgetStatePropertyAll(onPrimary),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: button.copyWith(
        backgroundColor: WidgetStatePropertyAll(card),
        foregroundColor: WidgetStatePropertyAll(primary),
        side: WidgetStatePropertyAll(BorderSide(color: border)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        textStyle: const TextStyle(fontSize: 12, fontFamily: '.SF Pro Text'),
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: primary,
        minimumSize: const Size(32, 32),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.all(14),
      dense: true,
      minVerticalPadding: 0,
      minLeadingWidth: 22,
      horizontalTitleGap: 12,
      textColor: primary,
      iconColor: muted,
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: border),
      shape: const StadiumBorder(),
      selectedColor: primary,
      showCheckmark: false,
      labelStyle: TextStyle(fontSize: 13, color: primary),
      secondaryLabelStyle: TextStyle(color: onPrimary),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      },
    ),
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
  Widget build(BuildContext context) {
    final back = Navigator.of(context).canPop();
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: SafeArea(
          bottom: false,
          child: Container(
            key: const Key('app.header'),
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: PanelDesign.background(context),
              border: Border(
                bottom: BorderSide(
                  color: PanelDesign.border(context),
                  width: .5,
                ),
              ),
            ),
            child: Row(
              children: [
                if (back)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Semantics(
                      label: '返回',
                      button: true,
                      child: GestureDetector(
                        key: const Key('app.back'),
                        onTap: () => Navigator.of(context).maybePop(),
                        behavior: HitTestBehavior.opaque,
                        child: const SizedBox(
                          width: 32,
                          height: 44,
                          child: Center(
                            child: PanelIcon(
                              Icons.arrow_back_ios_new,
                              size: 17,
                              weight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                ),
                const Spacer(),
                if (account) const Flexible(child: AccountSelector()),
                ...actions,
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(top: false, child: child),
    );
  }
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
        width: 235,
        height: 36,
        constraints: const BoxConstraints(maxWidth: 235),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Theme.of(context).inputDecorationTheme.fillColor,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                account?.name ?? '选择账户',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: PanelDesign.card(context),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                account?.zone ?? 'OVH',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 7),
            PanelIcon(
              Icons.expand_more,
              size: 10,
              color: PanelDesign.muted(context),
              weight: FontWeight.w500,
            ),
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
    this.padding = const EdgeInsets.all(16),
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
  final double maxWidth, spacing;
  final EdgeInsets padding;
  const PageList({
    super.key,
    required this.children,
    this.refresh,
    this.storageKey = '',
    this.maxWidth = 900,
    this.spacing = 14,
    this.padding = const EdgeInsets.all(14),
  });
  @override
  Widget build(BuildContext context) {
    final list = SingleChildScrollView(
      key: PageStorageKey(storageKey),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children
                .map(
                  (w) => Padding(
                    padding: EdgeInsets.only(
                      bottom: w == children.last ? 0 : spacing,
                    ),
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
      color: PanelDesign.warning.withValues(alpha: .06),
      border: Border.all(color: PanelDesign.warning.withValues(alpha: .3)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PanelIcon(
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
  final String subtitle;
  const EmptyPanel(
    this.title, {
    super.key,
    this.action,
    this.subtitle = '',
    this.icon = Icons.inbox_outlined,
  });
  @override
  Widget build(BuildContext context) => PanelCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        children: [
          PanelIcon(icon, size: 32, color: PanelDesign.muted(context)),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: PanelDesign.mutedText(context),
            ),
          ],
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
  Widget build(BuildContext c) {
    final tone = healthy ? PanelDesign.success : PanelDesign.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .08),
        border: Border.all(color: tone.withValues(alpha: .30)),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }
}

class FeatureRow extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback tap;
  final String? subtitle;
  final Color? iconColor;
  const FeatureRow(
    this.title, {
    super.key,
    required this.tap,
    this.icon = Icons.tune,
    this.subtitle,
    this.iconColor,
  });
  @override
  Widget build(BuildContext c) => Semantics(
    button: true,
    child: InkWell(
      onTap: tap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: PanelIcon(
                icon,
                size: 17,
                color: iconColor ?? PanelDesign.muted(c),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14)),
                  if (subtitle != null)
                    Text(subtitle!, style: PanelDesign.mutedText(c)),
                ],
              ),
            ),
            PanelIcon(
              Icons.chevron_right,
              size: 11,
              color: PanelDesign.muted(c),
            ),
          ],
        ),
      ),
    ),
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

/// Local expansion state must not share PageStorage with the scroll offset.
/// Expansible otherwise reads the parent scroll's double as a boolean.
class PanelDisclosure extends StatefulWidget {
  final Widget title;
  final List<Widget> children;
  final EdgeInsets padding;
  const PanelDisclosure({
    super.key,
    required this.title,
    required this.children,
    this.padding = const EdgeInsets.all(14),
  });
  @override
  State<PanelDisclosure> createState() => _PanelDisclosureState();
}

class _PanelDisclosureState extends State<PanelDisclosure> {
  bool expanded = false;
  @override
  Widget build(BuildContext c) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      InkWell(
        onTap: () => setState(() => expanded = !expanded),
        child: Padding(
          padding: widget.padding,
          child: SizedBox(
            height: 24,
            child: Row(
              children: [
                Expanded(child: widget.title),
                AnimatedRotation(
                  turns: expanded ? .25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: PanelIcon(
                    Icons.chevron_right,
                    size: 12,
                    color: PanelDesign.primary(c),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: expanded
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children,
              )
            : const SizedBox(width: double.infinity),
      ),
    ],
  );
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
            return PanelDisclosure(
              key: ValueKey('data.$key'),
              padding: EdgeInsets.zero,
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
                    style: TextStyle(
                      color: PanelDesign.muted(context),
                      fontSize: 13,
                    ),
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
  return await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: PanelDesign.background(context),
        builder: (c) => StatefulBuilder(
          builder: (c, update) => FractionallySizedBox(
            heightFactor: .94,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('取消'),
                      ),
                      const Expanded(
                        child: Text(
                          '确认操作',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 28),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(target, style: const TextStyle(fontSize: 14)),
                        if (danger) ...[
                          const SizedBox(height: 16),
                          const Notice('此操作会修改或删除当前目标的数据，请核对后确认。'),
                        ],
                        if (detail != null) ...[
                          const SizedBox(height: 16),
                          detail,
                        ],
                        if (typeTarget != null) ...[
                          const SizedBox(height: 16),
                          const Text(
                            '输入完整服务名称以确认',
                            style: TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            key: const Key('operation.confirmTarget'),
                            onChanged: (s) => update(() => typed = s),
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(hintText: typeTarget),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          key: const Key('operation.confirm'),
                          onPressed: typeTarget != null && typed != typeTarget
                              ? null
                              : () => Navigator.pop(c, true),
                          child: Text('确认$title'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ) ??
      false;
}

class AppTabSelection extends InheritedWidget {
  final ValueChanged<int> onSelected;
  const AppTabSelection({
    super.key,
    required this.onSelected,
    required super.child,
  });
  static ValueChanged<int>? of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<AppTabSelection>()?.onSelected;
  @override
  bool updateShouldNotify(AppTabSelection old) => false;
}

class SectionHeading extends StatelessWidget {
  final String title, subtitle;
  const SectionHeading(this.title, this.subtitle, {super.key});
  @override
  Widget build(BuildContext c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 5),
      Text(subtitle, style: PanelDesign.mutedText(c, 11)),
    ],
  );
}

class DividedRows extends StatelessWidget {
  final List<Widget> children;
  final double inset;
  const DividedRows(this.children, {super.key, this.inset = 48});
  @override
  Widget build(BuildContext c) => Column(
    children: [
      for (var i = 0; i < children.length; i++) ...[
        children[i],
        if (i < children.length - 1)
          Padding(
            padding: EdgeInsets.only(left: inset),
            child: const Divider(),
          ),
      ],
    ],
  );
}
