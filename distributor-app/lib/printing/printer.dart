import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

/// Bluetooth ESC/POS thermal printer (most portable printers: 58 and 80 mm).
/// The receipt is printed as a raster image.
class PrinterService {
  static Future<List<BluetoothInfo>> paired() async {
    if (!await PrintBluetoothThermal.isPermissionBluetoothGranted) return [];
    return PrintBluetoothThermal.pairedBluetooths;
  }

  static Future<bool> get bluetoothEnabled => PrintBluetoothThermal.bluetoothEnabled;

  /// Captures the widget under [key] (a RepaintBoundary) and prints it.
  static Future<void> printBoundary(GlobalKey key, {required String mac, required int paperMm}) async {
    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final dots = paperMm == 58 ? 384 : 576;
    final image = await boundary.toImage(pixelRatio: dots / boundary.size.width);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    await printPng(png, mac: mac, paperMm: paperMm);
  }

  static Future<void> printPng(Uint8List png, {required String mac, required int paperMm}) async {
    final decoded = img.decodePng(png);
    if (decoded == null) throw Exception('تعذر تجهيز صورة الفاتورة');
    final profile = await CapabilityProfile.load();
    final gen = Generator(paperMm == 58 ? PaperSize.mm58 : PaperSize.mm80, profile);
    final bytes = <int>[
      ...gen.reset(),
      ...gen.imageRaster(decoded, align: PosAlign.center),
      ...gen.feed(3),
      ...gen.cut(),
    ];
    if (!await PrintBluetoothThermal.connectionStatus) {
      final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      if (!ok) throw Exception('تعذر الاتصال بالطابعة. تأكد أنها مشغلة ومقترنة بالجوال.');
    }
    final ok = await PrintBluetoothThermal.writeBytes(bytes);
    if (!ok) throw Exception('فشل إرسال الفاتورة إلى الطابعة');
  }
}
