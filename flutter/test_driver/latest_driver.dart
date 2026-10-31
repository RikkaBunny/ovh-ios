import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final folder = Directory(
      Platform.environment['OVH_CAPTURE_DIR'] ?? 'screenshots/latest',
    );
    await folder.create(recursive: true);
    await File('${folder.path}/$name.png').writeAsBytes(bytes);
    return true;
  },
);
