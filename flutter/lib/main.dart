import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'core/models.dart';
import 'core/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'OVH client / gokele/ovh',
    ], await rootBundle.loadString('assets/LICENSE.txt'));
  });
  final catalog = Catalog(
    object(
      jsonDecode(await rootBundle.loadString('assets/NativeCatalog.json')),
    ),
  );
  runApp(OVHApp(store: PanelStore(catalog)));
}
