// Renders the main screens and a receipt to PNG files for review:
//   SCREENSHOTS_DIR=/tmp/shots FONTS_DIR=/path/with/DejaVuSans.ttf flutter test test/screenshots_test.dart
// Skipped when SCREENSHOTS_DIR is not set.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaif_distributor/data/api.dart';
import 'package:kaif_distributor/data/db.dart';
import 'package:kaif_distributor/data/models.dart';
import 'package:kaif_distributor/data/repository.dart';
import 'package:kaif_distributor/data/settings.dart';
import 'package:kaif_distributor/printing/receipt.dart';
import 'package:kaif_distributor/ui/customer_screen.dart';
import 'package:kaif_distributor/ui/home_screen.dart';
import 'package:kaif_distributor/ui/sale_screen.dart';
import 'package:kaif_distributor/ui/scope.dart';
import 'package:kaif_distributor/ui/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'repository_test.dart' show FakeServer;

final outDir = Platform.environment['SCREENSHOTS_DIR'];
final fontsDir = Platform.environment['FONTS_DIR'];

Future<void> loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

Future<void> shot(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 2);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$outDir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  sqfliteFfiInit();

  testWidgets('screenshots', skip: outDir == null, (tester) async {
    await tester.runAsync(() async {
      await loadFont('DejaVu', ['$fontsDir/DejaVuSans.ttf', '$fontsDir/DejaVuSans-Bold.ttf']);
      await loadFont('MaterialIcons', ['$fontsDir/MaterialIcons-Regular.otf']);
    });
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 2.75;

    late Repository repo;
    late Settings settings;
    late Doc invoice;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({'server': 'https://erp.alkaif.sa', 'user': 'ahmad', 'printerName': 'MPT-III'});
      settings = await Settings.load();
      final dir = await Directory.systemTemp.createTemp('kaif');
      repo = Repository(await LocalDb.open(factory: databaseFactoryFfi, path: '${dir.path}/s.db'))
        ..api = Api('http://x', 'u', 'p', client: FakeServer().client());
      await repo.load();
      await repo.download();
      final c = repo.data!.customer('KN1')!;
      invoice = await repo.saveInvoice(c, [SaleLine('NM1', 'شاي الكيف الأصلي 100 كيس', 'كرتون', 6000, 2000, 1500)], false, 5000,
          PayMethod.cash);
    });

    final key = GlobalKey();
    Widget app(Widget home) => AppScope(
          repo: repo,
          settings: settings,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: kaifTheme(fontFamily: 'DejaVu'),
            locale: const Locale('ar', 'SA'),
            supportedLocales: const [Locale('ar', 'SA')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => RepaintBoundary(
              key: key,
              child: DefaultTextStyle.merge(style: const TextStyle(fontFamily: 'DejaVu'), child: child!),
            ),
            home: home,
          ),
        );

    Future<void> render(Widget home, String name) async {
      await tester.pumpWidget(app(home));
      await tester.runAsync(() => precacheImage(const AssetImage('assets/logo.png'), key.currentContext!));
      await tester.pumpAndSettle();
      await shot(tester, key, name);
    }

    await render(const HomeScreen(), '1_customers');
    await render(const CustomerScreen(customerId: 'KN1'), '2_customer');
    await render(const SaleScreen(customerId: 'KN1'), '3_sale_empty');
    // add an item through the picker
    await tester.tap(find.text('إضافة صنف'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('شاي الكيف 100 كيس').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    await shot(tester, key, '3_sale');

    await render(
        Scaffold(
          backgroundColor: Colors.white,
          body: SingleChildScrollView(child: Center(child: Receipt(doc: invoice, company: repo.data!.company))),
        ),
        '4_receipt');
  });
}
