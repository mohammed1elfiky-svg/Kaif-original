import 'package:flutter_test/flutter_test.dart';
import 'package:kaif_distributor/core/money.dart';
import 'package:kaif_distributor/core/zatca.dart';

void main() {
  test('ZATCA QR matches the official ZATCA sample', () {
    final qr = zatcaQr(
      sellerName: 'Bobs Records',
      vatNumber: '310122393500003',
      timestamp: DateTime.utc(2022, 4, 25, 15, 30),
      totalWithVat: '1000.00',
      vatTotal: '150.00',
    );
    expect(qr,
        'AQxCb2JzIFJlY29yZHMCDzMxMDEyMjM5MzUwMDAwMwMUMjAyMi0wNC0yNVQxNTozMDowMFoEBzEwMDAuMDAFBjE1MC4wMA==');
  });

  test('ZATCA QR with an Arabic seller name matches the server formula', () {
    // value produced by the PostgreSQL formula of ZatcaQR.lsf for the same input (Riyadh 13:00 = 10:00Z)
    final qr = zatcaQr(
      sellerName: 'شركة كيف للتجارة',
      vatNumber: '300000000000003',
      timestamp: DateTime.utc(2026, 11, 13, 10),
      totalWithVat: '1150.50',
      vatTotal: '150.07',
    );
    expect(qr,
        'AR7YtNix2YPYqSDZg9mK2YEg2YTZhNiq2KzYp9ix2KkCDzMwMDAwMDAwMDAwMDAwMwMUMjAyNi0xMS0xM1QxMDowMDowMFoEBzExNTAuNTAFBjE1MC4wNw==');
  });

  test('parsing and formatting', () {
    expect(toHalalas('18.5'), 1850);
    expect(toHalalas(7.25), 725);
    expect(toHalalas('0.005'), 1);
    expect(toHalalas(null), 0);
    expect(toMilli('2.5'), 2500);
    expect(formatMoney(123456789), '1,234,567.89');
    expect(formatMoney(5, grouping: false), '0.05');
    expect(formatMoney(-1050), '-10.50');
    expect(formatQty(2500), '2.5');
    expect(formatQty(3000), '3');
  });

  test('line amounts: price without tax', () {
    final l = calcLine(qtyMilli: 24000, price: 1800, rate: 1500, taxIncluded: false);
    expect(l.untaxed, 43200);
    expect(l.tax, 6480);
    expect(l.total, 49680);
  });

  test('line amounts: price including tax', () {
    final l = calcLine(qtyMilli: 3000, price: 1150, rate: 1500, taxIncluded: true);
    expect(l.untaxed, 3450);
    expect(l.tax, 450);
    expect(l.total, 3450);
    expect(l.net, 3000);
  });

  test('line amounts: rounding half up', () {
    // 1.005 * 1 kg -> 0.10 * 15% = 0.015 -> 0.02
    final l = calcLine(qtyMilli: 1000, price: 10, rate: 1500, taxIncluded: false);
    expect(l.tax, 2);
  });
}
