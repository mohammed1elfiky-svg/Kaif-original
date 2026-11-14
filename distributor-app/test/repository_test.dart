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
  double onHand = 50;
  final uploads = <Map<String, dynamic>>[];
  String? lastAuth;

  Map<String, dynamic> data() => {
        'distributor': [
          {'id': 'E1', 'name': 'أحمد', 'prefix': 'D01', 'location': 'سيارة 1'}
        ],
        'company': [
          {'name': 'الكيف الأصلي', 'vat': '310122393500003', 'cr': '1010123456', 'address': 'الرياض', 'phone': '0500000000'}
        ],
        'customers': [
          {'id': 'KN1', 'name': 'بقالة النور', 'priceType': 'wholesale', 'creditLimit': 500, 'maxOverdueDays': 30, 'debt': debt, 'overdueDays': 0},
          {'id': 'KN2', 'name': 'مؤسسة متأخرة', 'priceType': 'wholesale', 'creditLimit': 10000, 'maxOverdueDays': 15, 'debt': 300, 'overdueDays': 40},
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
              onHand -= double.parse(l['quantity']);
            }
          }
          for (final p in (body['payments'] as List)) {
            res.add({'id': p['id'], 'result': 'ok'});
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
    repo = Repository(db)..api = Api('http://server:8080/', 'ahmad', 'secret', client: server.client());
    await repo.load();
    await repo.download();
  });

  test('download', () {
    expect(repo.data!.customers.length, 2);
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
    expect(repo.pendingCount, 2);

    await repo.sync();
    expect(repo.lastSyncError, isNull);
    expect(repo.pendingCount, 0);
    expect(server.uploads.length, 1);
    final inv = server.uploads.first['invoices'][0];
    expect(inv['number'], 'D01-000001');
    expect(inv['customer'], 'KN1');
    expect(inv['paid'], '10.00');
    expect(inv['lines'][0], {'item': 'NM1', 'quantity': '2.5', 'price': '20.00'});
    expect(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$').hasMatch(inv['date']), isTrue);
    final pay = server.uploads.first['payments'][0];
    expect(pay['amount'], '20.00');
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
    expect(again.docs.length, 1);
    expect(again.stock('NM1'), 49000);
    expect(again.docs.first.totals.total, 2300);
  });
}
