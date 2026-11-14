import 'dart:convert';
import 'dart:typed_data';

/// ZATCA e-invoicing phase 1 QR code: TLV (tag, length, value) fields encoded in Base64.
/// Must produce the same value as the server (region/sa/invoicing/zatca/ZatcaQR.lsf).
String zatcaQr({
  required String sellerName,
  required String vatNumber,
  required DateTime timestamp,
  required String totalWithVat,
  required String vatTotal,
}) {
  final bytes = BytesBuilder();
  void tlv(int tag, String value) {
    final data = utf8.encode(value);
    if (data.length > 255) {
      throw ArgumentError('ZATCA QR field $tag is longer than 255 bytes');
    }
    bytes
      ..addByte(tag)
      ..addByte(data.length)
      ..add(data);
  }

  tlv(1, sellerName);
  tlv(2, vatNumber);
  tlv(3, zatcaTimestamp(timestamp));
  tlv(4, totalWithVat);
  tlv(5, vatTotal);
  return base64.encode(bytes.toBytes());
}

/// ISO 8601 in UTC, e.g. 2022-04-25T15:30:00Z.
String zatcaTimestamp(DateTime t) {
  final u = t.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}'
      'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
}
