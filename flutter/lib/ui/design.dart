import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Values transcribed from Screens.swift, rather than Material defaults.
abstract final class PanelDesign {
  static Color background(BuildContext c) =>
      dark(c) ? const Color(0xff0f0f0f) : Colors.white;
  static Color card(BuildContext c) =>
      dark(c) ? const Color(0xff141414) : Colors.white;
  static Color secondary(BuildContext c) =>
      dark(c) ? const Color(0xff242424) : const Color(0xfff5f5f5);
  static Color border(BuildContext c) =>
      dark(c) ? const Color(0xff2e2e2e) : const Color(0xffe6e6e6);
  static Color primary(BuildContext c) =>
      dark(c) ? const Color(0xfff5f5f5) : const Color(0xff171717);
  static Color muted(BuildContext c) =>
      dark(c) ? const Color(0xff999999) : const Color(0xff737373);
  static bool dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  static const success = Color(0xff21c45e), warning = Color(0xfff59e0a);
  static TextStyle mutedText(BuildContext c, [double size = 12]) =>
      TextStyle(fontSize: size, color: muted(c));
}

/// iOS uses exactly the SF Symbols used by the SwiftUI reference. The native
/// bridge renders system glyphs; other platforms retain a local vector fallback.
class _SystemSymbol {
  final Uint8List bytes;
  final double width, height;
  _SystemSymbol(this.bytes, this.width, this.height);
}

class PanelIcon extends StatelessWidget {
  final IconData? icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final FontWeight weight;
  const PanelIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.weight = FontWeight.w400,
  });
  static const _channel = MethodChannel('ovh_cp/system_symbol');
  static final _cache = <String, Future<_SystemSymbol?>>{};
  static final symbols = <IconData, String>{
    Icons.bar_chart_outlined: 'chart.bar',
    Icons.dns_outlined: 'server.rack',
    Icons.assignment_outlined: 'list.clipboard',
    Icons.notifications_none: 'bell',
    Icons.more_horiz: 'ellipsis',
    Icons.chevron_right: 'chevron.right',
    Icons.expand_more: 'chevron.down',
    Icons.arrow_back_ios_new: 'chevron.left',
    Icons.inbox_outlined: 'tray',
    Icons.tune: 'slider.horizontal.3',
    Icons.warning_amber_rounded: 'exclamationmark.triangle',
    Icons.warning_amber_outlined: 'exclamationmark.circle',
    Icons.arrow_forward: 'arrow.right',
    Icons.flash_on_outlined: 'bolt',
    Icons.add: 'plus',
    Icons.remove: 'minus',
    Icons.event_note_outlined: 'calendar',
    Icons.refresh: 'arrow.clockwise',
    Icons.search: 'magnifyingglass',
    Icons.inventory_2_outlined: 'shippingbox',
    Icons.cloud_outlined: 'cloud',
    Icons.person_outline: 'person.crop.circle',
    Icons.history: 'clock.arrow.circlepath',
    Icons.article_outlined: 'doc.text',
    Icons.settings_outlined: 'slider.horizontal.3',
    Icons.phone_iphone: 'iphone',
    Icons.qr_code: 'qrcode',
    Icons.qr_code_scanner: 'qrcode.viewfinder',
    Icons.photo_outlined: 'photo',
    Icons.link: 'link',
    Icons.copy: 'doc.on.doc',
    Icons.check: 'checkmark',
    Icons.ios_share: 'square.and.arrow.up',
    Icons.description_outlined: 'doc.text',
    Icons.desktop_windows_outlined: 'desktopcomputer',
    Icons.clear: 'xmark.circle.fill',
    Icons.layers_outlined: 'square.3.layers.3d',
    Icons.circle_outlined: 'circle',
    Icons.check_circle_outline: 'checkmark.circle',
    Icons.timer_outlined: 'timer',
    Icons.key_outlined: 'key',
    Icons.arrow_downward: 'arrow.down',
    Icons.arrow_upward: 'arrow.up',
    Icons.show_chart: 'chart.xyaxis.line',
    Icons.wifi: 'wifi',
    Icons.memory: 'cpu',
    Icons.developer_board_outlined: 'memorychip',
    Icons.storage_outlined: 'internaldrive',
    Icons.remove_circle_outline: 'minus.circle',
    Icons.apps_outlined: 'square.grid.2x2',
    Icons.language: 'network',
    Icons.lock_outline: 'lock.shield',
  };
  static final _lineIcons = <IconData, IconData>{
    Icons.bar_chart_outlined: CupertinoIcons.chart_bar,
    Icons.dns_outlined: CupertinoIcons.square_stack,
    Icons.assignment_outlined: CupertinoIcons.list_bullet,
    Icons.notifications_none: CupertinoIcons.bell,
    Icons.more_horiz: CupertinoIcons.ellipsis,
    Icons.chevron_right: CupertinoIcons.chevron_right,
    Icons.expand_more: CupertinoIcons.chevron_down,
    Icons.arrow_back_ios_new: CupertinoIcons.chevron_left,
    Icons.inbox_outlined: CupertinoIcons.tray,
    Icons.tune: CupertinoIcons.slider_horizontal_3,
    Icons.warning_amber_rounded: CupertinoIcons.exclamationmark_triangle,
    Icons.warning_amber_outlined: CupertinoIcons.exclamationmark_circle,
    Icons.arrow_forward: CupertinoIcons.arrow_right,
    Icons.flash_on_outlined: CupertinoIcons.bolt,
    Icons.add: CupertinoIcons.plus,
    Icons.remove: CupertinoIcons.minus,
    Icons.event_note_outlined: CupertinoIcons.calendar,
    Icons.refresh: CupertinoIcons.arrow_clockwise,
    Icons.search: CupertinoIcons.search,
    Icons.inventory_2_outlined: CupertinoIcons.cube_box,
    Icons.cloud_outlined: CupertinoIcons.cloud,
    Icons.person_outline: CupertinoIcons.person_crop_circle,
    Icons.history: CupertinoIcons.clock,
    Icons.article_outlined: CupertinoIcons.doc_text,
    Icons.settings_outlined: CupertinoIcons.slider_horizontal_3,
    Icons.phone_iphone: CupertinoIcons.device_phone_portrait,
    Icons.qr_code: CupertinoIcons.qrcode,
    Icons.qr_code_scanner: CupertinoIcons.qrcode_viewfinder,
    Icons.photo_outlined: CupertinoIcons.photo,
    Icons.link: CupertinoIcons.link,
    Icons.copy: CupertinoIcons.doc_on_doc,
    Icons.check: CupertinoIcons.check_mark,
    Icons.ios_share: CupertinoIcons.square_arrow_up,
    Icons.description_outlined: CupertinoIcons.doc_text,
    Icons.desktop_windows_outlined: CupertinoIcons.desktopcomputer,
    Icons.clear: CupertinoIcons.xmark_circle_fill,
    Icons.layers_outlined: CupertinoIcons.square_stack_3d_up,
    Icons.circle_outlined: CupertinoIcons.circle,
    Icons.check_circle_outline: CupertinoIcons.check_mark_circled,
    Icons.timer_outlined: CupertinoIcons.timer,
    Icons.remove_circle_outline: CupertinoIcons.minus_circle,
    Icons.apps_outlined: CupertinoIcons.square_grid_2x2,
    Icons.language: CupertinoIcons.globe,
    Icons.lock_outline: CupertinoIcons.lock_shield,
    Icons.wifi: CupertinoIcons.wifi,
    Icons.arrow_downward: CupertinoIcons.arrow_down,
    Icons.arrow_upward: CupertinoIcons.arrow_up,
    Icons.show_chart: CupertinoIcons.graph_square,
  };
  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context), points = size ?? 17;
    final tint = color ?? theme.color ?? PanelDesign.primary(context);
    final symbol = symbols[icon];
    if (defaultTargetPlatform != TargetPlatform.iOS || symbol == null) {
      return Icon(
        _lineIcons[icon] ?? icon,
        size: points,
        color: tint,
        semanticLabel: semanticLabel,
      );
    }
    final key = '$symbol:$points:${weight.value}';
    final future = _cache.putIfAbsent(key, () async {
      try {
        final rendered = await _channel.invokeMapMethod<String, dynamic>(
          'render',
          {'name': symbol, 'size': points, 'weight': weight.value},
        );
        return rendered == null
            ? null
            : _SystemSymbol(
                rendered['data'] as Uint8List,
                (rendered['width'] as num).toDouble(),
                (rendered['height'] as num).toDouble(),
              );
      } on PlatformException {
        return null;
      } on MissingPluginException {
        return null;
      }
    });
    return Semantics(
      label: semanticLabel,
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: SizedBox(
          width: points,
          height: points,
          child: FutureBuilder<_SystemSymbol?>(
            future: future,
            builder: (_, state) => state.data == null
                ? Icon(_lineIcons[icon] ?? icon, size: points, color: tint)
                : OverflowBox(
                    minWidth: 0,
                    minHeight: 0,
                    maxWidth: points * 2,
                    maxHeight: points * 2,
                    child: Image.memory(
                      state.data!.bytes,
                      width: state.data!.width,
                      height: state.data!.height,
                      color: tint,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class PanelSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const PanelSwitch({super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext c) => CupertinoSwitch(
    value: value,
    onChanged: onChanged,
    activeTrackColor: PanelDesign.primary(c),
    inactiveTrackColor: PanelDesign.dark(c)
        ? const Color(0xff3a3a3c)
        : const Color(0xffe9e9eb),
  );
}

class PanelSegments extends StatelessWidget {
  final List<String> values;
  final String selected;
  final ValueChanged<String> onChanged;
  final String? keyPrefix;
  final bool capsule;
  const PanelSegments({
    super.key,
    required this.values,
    required this.selected,
    required this.onChanged,
    this.keyPrefix,
    this.capsule = false,
  });
  @override
  Widget build(BuildContext c) => Container(
    padding: EdgeInsets.all(capsule ? 4 : 2),
    decoration: BoxDecoration(
      color: PanelDesign.secondary(c),
      borderRadius: BorderRadius.circular(capsule ? 50 : 8),
    ),
    child: Row(
      children: values
          .map(
            (v) => Expanded(
              child: Semantics(
                selected: v == selected,
                button: true,
                child: GestureDetector(
                  key: keyPrefix == null ? null : Key('$keyPrefix$v'),
                  onTap: () => onChanged(v),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: capsule ? 36 : 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: v == selected
                          ? PanelDesign.card(c)
                          : Colors.transparent,
                      border: v == selected
                          ? Border.all(
                              color: PanelDesign.border(c),
                              width: capsule ? 1 : .5,
                            )
                          : null,
                      borderRadius: BorderRadius.circular(capsule ? 50 : 6),
                      boxShadow: !capsule && v == selected
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: .08),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      v,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: v == selected
                            ? FontWeight.w500
                            : FontWeight.w400,
                        color: v == selected
                            ? PanelDesign.primary(c)
                            : PanelDesign.muted(c),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    ),
  );
}
