import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaif_distributor/data/api.dart';
import 'package:kaif_distributor/data/db.dart';
import 'package:kaif_distributor/data/models.dart';
import 'package:kaif_distributor/data/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A fake lsFusion server: serves getData and records uploads.
class FakeServer {
  double debt = 100;
  String? lastInvoice;
  double onHand = 50;
  final uploads = <Map<String, dynamic>>[];
  String? lastAuth;

  Map<String, dynamic> data() => {
        'distributor': [
          {'id': 'E1', 'name': 'أحمد', 'prefix': 'D01', 'location': 'سيارة 1', 'lastInvoice': lastInvoice}
        ],
        'company': [
          {'name': 'الكيف الأصلي', 'vat': '310122393500003', 'cr': '1010123456', 'address': 'الرياض', 'phone': '0500000000'}
        ],
        'customers': [
          {'id': 'KN1', 'name': 'بقالة النور', 'priceType': 'wholesale', 'creditLimit': 500, 'maxOverdueDays': 30, 'debt': debt, 'overdueDays': 0, 'visitDays': '6,7', 'visitOrder': 2},
          {'id': 'KN2', 'name': 'مؤسسة متأخرة', 'priceType': 'wholesale', 'creditLimit': 10000, 'maxOverdueDays': 15, 'debt': 300, 'overdueDays': 40, 'visitDays': '7', 'visitOrder': 1},
          {'id': 'KN3', 'name': 'سوبرماركت الخير', 'priceType': 'wholesale', 'debt': 0, 'visitDays': '1,3'},
        ],
        'openInvoices': [
          {'customer': 'KN1', 'number': 'INV-1', 'date': '2026-11-01T10:00:00', 'amount': 100, 'left': debt}
        ],
        'items': [
          {'id': 'NM1', 'name': 'شاي الكيف 100 كيس', 'barcode': '628000', 'uom': 'كرتون', 'tax': 15, 'onHand': onHand}
        ],
        'prices': [
          {'priceType': 'wholesale', 'taxIncluded': false, 'item': 'NM1', 'price': 20}
        ],
      };

  MockClient client() => MockClient((req) async {
        lastAuth = req.headers['Authorization'];
        if (req.url.path.endsWith('Distribution.getData')) {
          return http.Response.bytes(utf8.encode(jsonEncode(data())), 200);
        }
        if (req.url.path.endsWith('Distribution.upload')) {
          final body = jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>;
          uploads.add(body);
          final res = <Map<String, String>>[];
          for (final i in (body['invoices'] as List)) {
            res.add({'id': i['id'], 'result': 'ok'});
            // the server now has the sale
            for (final l in i['lines']) {
              onHand -= (l['quantity'] as num).toDouble();
            }
          }
          for (final r in (body['returns'] as List)) {
            res.add({'id': r['id'], 'result': 'ok'});
            for (final l in r['lines']) {
              onHand += (l['quantity'] as num).toDouble();
            }
          }
          for (final k in ['payments', 'visits', 'closings']) {
            for (final p in (body[k] as List)) {
              res.add({'id': p['id'], 'result': 'ok'});
            }
          }
          return http.Response.bytes(utf8.encode(jsonEncode(res)), 200);
        }
        return http.Response('not found', 404);
      });
}

void main() {
  sqfliteFfiInit();

  late FakeServer server;
  late Repository repo;

  setUp(() async {
    server = FakeServer();
    final dir = await Directory.systemTemp.createTemp('kaif');
    final db = await LocalDb.open(factory: databaseFactoryFfi, path: '${dir.path}/test.db');
    repo = Repository(db)
      ..api = Api('http://server:8080/', 'ahmad', 'secret', client: server.client())
      ..locate = (() async => (latitude: 24.7136, longitude: 46.6753))
      // Sunday 2026-11-15, 10:00 in Riyadh
      ..now = () => DateTime.utc(2026, 11, 15, 7);
    await repo.load();
    await repo.download();
  });

  test('download', () {
    expect(repo.data!.customers.length, 3);
    expect(repo.stock('NM1'), 50000);
    expect(server.lastAuth, 'Basic ${base64.encode(utf8.encode('ahmad:secret'))}');
  });

  test('sale offline: stock, debt, numbering, credit control', () async {
    final c = repo.data!.customer('KN1')!;
    final p = repo.price(c, 'NM1')!;
    final lines = [SaleLine('NM1', 'شاي', 'كرتون', 10000, p.price, 1500)]; // 10 x 20.00 + 15%
    final total = Doc(id: 'x', kind: DocKind.invoice, number: '', date: DateTime.now(), customerId: c.id,
            customerName: c.name, lines: lines)
        .totals
        .total;
    expect(total, 23000);

    // debt 100 + credit 230 = 330 <= 500: allowed on credit
    expect(repo.checkSale(c, total, 0).ok, isTrue);
    final inv = await repo.saveInvoice(c, lines, p.taxIncluded, 0, PayMethod.cash);
    expect(inv.number, 'D01-000001');
    expect(repo.stock('NM1'), 40000);
    expect(repo.debt(c), 33000);
    expect(repo.availableCredit(c), 17000);

    // second credit sale of 230 would exceed the limit, half cash is fine
    expect(repo.checkSale(c, total, 0).ok, isFalse);
    expect(repo.checkSale(c, total, 10000).ok, isTrue);
    final inv2 = await repo.saveInvoice(c, lines, false, total, PayMethod.cash);
    expect(inv2.number, 'D01-000002');

    // collection
    final pay = await repo.savePayment(c, 5000, PayMethod.cash);
    expect(pay.number, 'D01-R-000001');
    expect(repo.debt(c), 28000);
  });

  test('overdue customer: cash only', () {
    final c = repo.data!.customer('KN2')!;
    expect(repo.checkSale(c, 1000, 0).ok, isFalse);
    expect(repo.checkSale(c, 1000, 1000).ok, isTrue);
  });

  test('sync uploads the documents once and refreshes the data', () async {
    final c = repo.data!.customer('KN1')!;
    await repo.saveInvoice(c, [SaleLine('NM1', 'شاي', 'كرتون', 2500, 2000, 1500)], false, 1000, PayMethod.cash);
    await repo.savePayment(c, 2000, PayMethod.bank, invoiceNumber: 'INV-1');
    expect(repo.pendingCount, 4); // 2 documents + 2 visits logged with them

    await repo.sync();
    expect(repo.lastSyncError, isNull);
    expect(repo.pendingCount, 0);
    expect(server.uploads.length, 1);
    expect(server.uploads.first['visits'].length, 2); // logged automatically with the sale and the collection
    expect(server.uploads.first['visits'][0]['latitude'], 24.7136);
    expect(server.uploads.first['visits'][0]['result'], 'sale');
    final inv = server.uploads.first['invoices'][0];
    expect(inv['number'], 'D01-000001');
    expect(inv['customer'], 'KN1');
    expect(inv['paid'], 10.0);
    expect(inv['lines'][0], {'item': 'NM1', 'quantity': 2.5, 'price': 20.0});
    expect(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$').hasMatch(inv['date']), isTrue);
    final pay = server.uploads.first['payments'][0];
    expect(pay['amount'], 20.0);
    expect(pay['method'], 'bank');
    expect(pay['invoice'], 'INV-1');

    // after the download the sale is part of the server stock: not subtracted twice
    expect(repo.stock('NM1'), 47500);

    // nothing left to send
    await repo.sync();
    expect(server.uploads.length, 1);
  });

  test('documents survive a restart', () async {
    final c = repo.data!.customer('KN1')!;
    await repo.saveInvoice(c, [SaleLine('NM1', 'شاي', 'كرتون', 1000, 2000, 1500)], false, 0, PayMethod.cash);
    final again = Repository(repo.db);
    await again.load();
    expect(again.docs.where((d) => d.kind == DocKind.invoice).length, 1);
    expect(again.stock('NM1'), 49000);
    expect(again.docs.first.totals.total, 2300);
  });

  test('return: goods back to the van, debt decreased or cash refunded', () async {
    final c = repo.data!.customer('KN1')!;
    final lines = [SaleLine('NM1', 'شاي', 'كرتون', 2000, 2000, 1500)]; // 2 x 20 + 15% = 46
    final r = await repo.saveReturn(c, lines, false, 0, invoiceNumber: 'INV-1', reason: 'تالف');
    expect(r.number, 'D01-C-000001');
    expect(repo.stock('NM1'), 52000);
    expect(repo.debt(c), 10000 - 4600);

    final r2 = await repo.saveReturn(c, lines, false, 4600, reason: 'تالف');
    expect(repo.debt(c), 10000 - 4600); // refunded in cash: the debt does not change
    expect(repo.daySummary().cashRefunds, 4600);
    expect(repo.daySummary().cashExpected, -4600);

    final up = r2.toUploadJson();
    expect(up['refund'], 46.0);
    expect(up['reason'], 'تالف');
    expect(r.toUploadJson()['invoice'], 'INV-1');
    expect(up['lines'][0], {'item': 'NM1', 'quantity': 2, 'price': 20.0});

    await repo.sync();
    expect(server.uploads.single['returns'].length, 2);
    expect(repo.stock('NM1'), 54000); // the server has the returns now, not counted twice
  });

  test('route of the day and visits', () async {
    // Sunday: KN2 (order 1), then KN1 (order 2); KN3 visits on Monday and Wednesday
    expect(repo.todayRoute().map((c) => c.id), ['KN2', 'KN1']);
    final kn1 = repo.data!.customer('KN1')!;
    expect(repo.visitedToday(kn1), isFalse);
    final v = await repo.logVisit(kn1, 'closed', note: 'مغلق للصلاة');
    expect(repo.visitedToday(kn1), isTrue);
    expect(v.toUploadJson(), {
      'id': v.id,
      'date': '2026-11-15T10:00:00',
      'customer': 'KN1',
      'latitude': 24.7136,
      'longitude': 46.6753,
      'result': 'closed',
      'note': 'مغلق للصلاة',
    });
    // the next day nobody is visited yet
    repo.now = () => DateTime.utc(2026, 11, 16, 7);
    expect(repo.visitedToday(kn1), isFalse);
    expect(repo.todayRoute().map((c) => c.id), ['KN3']);
  });

  test('closing of the day', () async {
    final c = repo.data!.customer('KN1')!;
    // cash sale 46, credit sale 23, bank collection 10, cash collection 5
    await repo.saveInvoice(c, [SaleLine('NM1', 'شاي', 'كرتون', 2000, 2000, 1500)], false, 4600, PayMethod.cash);
    await repo.saveInvoice(c, [SaleLine('NM1', 'شاي', 'كرتون', 1000, 2000, 1500)], false, 0, PayMethod.cash);
    await repo.savePayment(c, 1000, PayMethod.bank);
    await repo.savePayment(c, 500, PayMethod.cash);
    final s = repo.daySummary();
    expect(s.sales, 6900);
    expect(s.credit, 2300);
    expect(s.cashExpected, 5100);
    expect(s.bank, 1000);
    expect(s.invoices, 2);
    expect(s.visits, 4);

    expect(repo.stock('NM1'), 47000);
    repo.now = () => DateTime.utc(2026, 11, 15, 15);
    final z = await repo.saveClosing({'NM1': 46000}, 5000, note: 'نقص كرتون');
    expect(z.number, 'D01-Z-000001');
    expect(z.closingLines.single.difference, -1000);
    final up = z.toUploadJson();
    expect(up['cashExpected'], 51.0);
    expect(up['cashHanded'], 50.0);
    expect(up['sales'], 69.0);
    expect(up['lines'], [
      {'item': 'NM1', 'expected': 47, 'counted': 46}
    ]);

    // a new day starts after the closing
    repo.now = () => DateTime.utc(2026, 11, 16, 7);
    expect(repo.daySummary().sales, 0);
    expect(repo.printableDocs.any((d) => d.kind == DocKind.visit), isFalse);

    await repo.sync();
    expect(server.uploads.single['closings'].length, 1);
  });

  test('numbering continues after the last number on the server (reinstall)', () async {
    server.lastInvoice = 'D01-000041';
    await repo.download();
    final c = repo.data!.customer('KN1')!;
    final inv = await repo.saveInvoice(c, [SaleLine('NM1', 'شاي', 'كرتون', 1000, 2000, 1500)], false, 2300, PayMethod.cash);
    expect(inv.number, 'D01-000042');
    // a lower number from the server does not move the counter back
    server.lastInvoice = 'D01-000005';
    await repo.download();
    final inv2 = await repo.saveInvoice(c, [SaleLine('NM1', 'شاي', 'كرتون', 1000, 2000, 1500)], false, 2300, PayMethod.cash);
    expect(inv2.number, 'D01-000043');
    expect(numberSequence('D01-R-000123'), 123);
  });

  test('cartons and pieces', () {
    final it = Item('NM9', 'شاي', '', 'حبة', 1500, 0, 'كرتون', 24000);
    expect(formatPacks(30000, it), '1 كرتون + 6 حبة');
    expect(formatPacks(48000, it), '2 كرتون');
    expect(formatPacks(5000, it), '5 حبة');
    expect(formatPacks(5000, Item('NM8', 'x', '', 'كغ', 0, 0)), '5 كغ');
  });
}
