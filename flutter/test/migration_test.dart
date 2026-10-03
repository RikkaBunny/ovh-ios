import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ovh_flutter/core/store.dart';
import 'package:ovh_flutter/core/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic>? previous;
  var clears = 0;
  var reads = 0;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    previous = {
      'address': 'https://panel.example',
      'secret': 'synthetic-device-token',
      'deviceToken': true,
      'deviceId': 17,
      'account': 'US',
      'appearance': 'dark',
    };
    clears = 0;
    reads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SecureCredentials.legacy, (call) async {
          if (call.method == 'read') {
            reads++;
            return previous;
          }
          if (call.method == 'clear') {
            clears++;
            previous = null;
          }
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SecureCredentials.legacy, null);
  });

  test(
    'Upgrade keeps device auth, region and appearance; migrates once',
    () async {
      final credentials = SecureCredentials();
      final connection = await credentials.read();
      expect(connection!.deviceToken, isTrue);
      expect(connection.deviceId, 17);
      expect(connection.secret, 'synthetic-device-token');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('ovh.account'), 'US');
      expect(preferences.getString('ovh.appearance'), 'dark');
      expect(clears, 1);
      expect((await credentials.read())!.deviceId, 17);
      expect(reads, 1);
    },
  );

  test(
    'Existing Flutter connection takes precedence over legacy data',
    () async {
      final connection = Connection.validated('https://new.example', 'new-key');
      FlutterSecureStorage.setMockInitialValues({
        SecureCredentials.key: jsonEncode(connection.toJson()),
      });
      expect(
        (await SecureCredentials().read())!.address,
        'https://new.example',
      );
      expect(reads, 0);
      expect(clears, 0);
    },
  );

  test(
    'Invalid legacy URL leaves original credential available for recovery',
    () async {
      previous!['address'] = 'http://panel.example';
      await expectLater(
        SecureCredentials().read(),
        throwsA(isA<PanelException>()),
      );
      expect(clears, 0);
      expect(
        await SecureCredentials().storage.read(key: SecureCredentials.key),
        isNull,
      );
    },
  );

  test(
    'Disconnect deletes both stores and cannot revive old authorization',
    () async {
      final credentials = SecureCredentials();
      await credentials.read();
      await credentials.delete();
      expect(await credentials.read(), isNull);
      expect(previous, isNull);
    },
  );

  test(
    'Upgrade does not overwrite already chosen Flutter preferences',
    () async {
      SharedPreferences.setMockInitialValues({
        'ovh.account': 'EU',
        'ovh.appearance': 'light',
      });
      await SecureCredentials().read();
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('ovh.account'), 'EU');
      expect(preferences.getString('ovh.appearance'), 'light');
    },
  );
}
