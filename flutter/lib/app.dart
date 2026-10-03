import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/api.dart';
import 'core/store.dart';
import 'ui/common.dart';
import 'ui/pairing_page.dart';
import 'ui/dashboard.dart';
import 'ui/instances.dart';
import 'ui/pages.dart';

class OVHApp extends StatefulWidget {
  final PanelStore store;
  final bool restore;
  const OVHApp({super.key, required this.store, this.restore = true});
  @override
  State<OVHApp> createState() => _OVHAppState();
}

class _OVHAppState extends State<OVHApp> {
  @override
  void initState() {
    super.initState();
    if (widget.restore) unawaited(restore());
  }

  Future<void> restore() async {
    await widget.store.restore();
    if (qaEnabled && widget.store.connection == null) {
      await widget.store.connect(
        'https://localhost:16443',
        'OVH-AppReview-2026',
      );
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: widget.store.appearance,
    builder: (context, appearance, _) => MaterialApp(
      title: 'OVH',
      debugShowCheckedModeBanner: false,
      theme: panelTheme(Brightness.light),
      darkTheme: panelTheme(Brightness.dark),
      themeMode: switch (appearance) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      builder: (context, child) =>
          PanelScope(store: widget.store, child: child!),
      home: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) => widget.store.connection == null
            ? const PairingPage()
            : AppShell(key: ValueKey(widget.store.session)),
      ),
    ),
  );
}

class StackObserver extends NavigatorObserver {
  int depth = 0;
  @override
  void didPush(Route route, Route? previousRoute) {
    depth++;
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    depth--;
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    depth--;
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int tab = 0, ticks = 0;
  bool foreground = true;
  final keys = List.generate(5, (_) => GlobalKey<NavigatorState>());
  final observers = List.generate(5, (_) => StackObserver());
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void poll() {
    if (!mounted || !foreground || observers[tab].depth > 1) return;
    final store = PanelScope.of(context);
    ticks++;
    if (tab == 0) {
      unawaited(store.load('/system/metrics', unknownOnFailure: true));
    }
    if (ticks % 5 == 0 && tab == 2) unawaited(store.load('/queue'));
    if (ticks % 5 == 0 && tab == 3) {
      unawaited(store.load('/monitor/subscriptions'));
      unawaited(store.load('/monitor/status'));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground && mounted) {
      unawaited(PanelScope.of(context).refreshOverview());
      poll();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) async {
      if (!didPop) await keys[tab].currentState?.maybePop();
    },
    child: Scaffold(
      body: IndexedStack(
        index: tab,
        children: List.generate(
          5,
          (index) => Navigator(
            key: keys[index],
            observers: [observers[index]],
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => [
                const DashboardPage(),
                const InstancesPage(),
                const QueuePage(),
                const MonitorPage(),
                const MorePage(),
              ][index],
            ),
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (index) {
            setState(() => tab = index);
            poll();
          },
          destinations: const [
            NavigationDestination(
              key: Key('tab.dashboard'),
              icon: Icon(Icons.bar_chart_outlined),
              label: '仪表盘',
            ),
            NavigationDestination(
              key: Key('tab.instances'),
              icon: Icon(Icons.dns_outlined),
              label: '服务器',
            ),
            NavigationDestination(
              key: Key('tab.queue'),
              icon: Icon(Icons.assignment_outlined),
              label: '队列',
            ),
            NavigationDestination(
              key: Key('tab.monitor'),
              icon: Icon(Icons.notifications_none),
              label: '监控',
            ),
            NavigationDestination(
              key: Key('tab.more'),
              icon: Icon(Icons.more_horiz),
              label: '更多',
            ),
          ],
        ),
      ),
    ),
  );
}
