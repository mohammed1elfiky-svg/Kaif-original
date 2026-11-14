import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'db.dart';
import 'models.dart';

class SaleCheck {
  final String? error; // the sale is not allowed
  const SaleCheck([this.error]);
  bool get ok => error == null;
}

/// State of the app: server data + documents made on the device, and the van stock and
/// customer debts adjusted by the documents that are not in the server data yet.
class Repository extends ChangeNotifier {
  final LocalDb db;
  Api? api;

  ServerData? data;
  DateTime? downloadedAt;
  List<Doc> docs = [];
  bool syncing = false;
  String? lastSyncError;

  Repository(this.db);

  Future<void> load() async {
    final json = await db.get('data');
    data = json == null ? null : ServerData.fromJson(jsonDecode(json));
    final at = await db.get('downloadedAt');
    downloadedAt = at == null ? null : DateTime.parse(at);
    docs = await db.docs();
    notifyListeners();
  }

  bool get hasData => data != null;

  Iterable<Doc> get _local => docs.where((d) => !d.inSnapshot);
  int get pendingCount => docs.where((d) => d.status != DocStatus.sent).length;

  /// van stock: as of download minus what was sold after it
  int stock(String itemId) {
    final base = data?.item(itemId)?.onHand ?? 0;
    var sold = 0;
    for (final d in _local.where((d) => d.kind == DocKind.invoice)) {
      for (final l in d.lines.where((l) => l.itemId == itemId)) {
        sold += l.qty;
      }
    }
    return base - sold;
  }

  /// customer debt: as of download plus the credit sales and minus the collections made after it
  int debt(Customer c) {
    var v = c.debt;
    for (final d in _local.where((d) => d.customerId == c.id)) {
      v += d.kind == DocKind.invoice ? d.credit : -d.paid;
    }
    return v;
  }

  int? availableCredit(Customer c) {
    if (c.creditLimit == null) return null;
    final d = debt(c);
    return c.creditLimit! - (d > 0 ? d : 0);
  }

  /// Credit control, the same rules as the server (DebtLimit.lsf): a sale with an unpaid part
  /// is refused when the customer has overdue debts for too long or the credit limit would be exceeded.
  SaleCheck checkSale(Customer c, int total, int paid) {
    final credit = total - paid;
    if (credit <= 0) return const SaleCheck();
    if (c.maxOverdueDays != null && c.overdueDays > c.maxOverdueDays!) {
      return SaleCheck('لدى العميل ديون متأخرة ${c.overdueDays} يوماً (المسموح ${c.maxOverdueDays}). '
          'البيع نقداً فقط.');
    }
    final available = availableCredit(c);
    if (available != null && credit > available) {
      return const SaleCheck('تم تجاوز الحد الائتماني للعميل. ادفع جزءاً أكبر نقداً.');
    }
    return const SaleCheck();
  }

  /// price of the item for the customer (by the customer's price type)
  Price? price(Customer c, String itemId) => data?.price(c.priceType, itemId);

  Future<Doc> saveInvoice(Customer c, List<SaleLine> lines, bool taxIncluded, int paid, PayMethod method,
      {String note = ''}) async {
    final doc = await db.insertDoc(
        (number) => Doc(
              id: const Uuid().v4(),
              kind: DocKind.invoice,
              number: number,
              date: DateTime.now().toUtc(),
              customerId: c.id,
              customerName: c.name,
              customerVat: c.vat,
              taxIncluded: taxIncluded,
              lines: lines,
              paid: paid,
              method: method,
              note: note,
            ),
        data!.distributor.prefix,
        DocKind.invoice);
    docs.insert(0, doc);
    notifyListeners();
    return doc;
  }

  Future<Doc> savePayment(Customer c, int amount, PayMethod method, {String invoiceNumber = '', String note = ''}) async {
    final doc = await db.insertDoc(
        (number) => Doc(
              id: const Uuid().v4(),
              kind: DocKind.payment,
              number: number,
              date: DateTime.now().toUtc(),
              customerId: c.id,
              customerName: c.name,
              customerVat: c.vat,
              paid: amount,
              method: method,
              invoiceNumber: invoiceNumber,
              note: note,
            ),
        data!.distributor.prefix,
        DocKind.payment);
    docs.insert(0, doc);
    notifyListeners();
    return doc;
  }

  /// Uploads the documents not received by the server yet, then downloads fresh data.
  Future<void> sync() async {
    if (api == null || syncing) return;
    syncing = true;
    lastSyncError = null;
    notifyListeners();
    try {
      final toSend = docs.where((d) => d.status != DocStatus.sent).toList().reversed.toList();
      if (toSend.isNotEmpty) {
        final result = await api!.upload(
          toSend.where((d) => d.kind == DocKind.invoice).map((d) => d.toUploadJson()).toList(),
          toSend.where((d) => d.kind == DocKind.payment).map((d) => d.toUploadJson()).toList(),
        );
        for (final d in toSend) {
          final r = result[d.id];
          if (r == null) continue;
          d.status = r == 'ok' ? DocStatus.sent : DocStatus.error;
          d.error = r == 'ok' ? '' : r;
          await db.setStatus(d.id, d.status, d.error);
        }
      }
      await download();
    } catch (e) {
      lastSyncError = e.toString();
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> download() async {
    final json = await api!.getData();
    final fresh = ServerData.fromJson(json);
    await db.put('data', jsonEncode(json));
    downloadedAt = DateTime.now();
    await db.put('downloadedAt', downloadedAt!.toIso8601String());
    await db.markSentInSnapshot();
    data = fresh;
    docs = await db.docs();
    notifyListeners();
  }

  /// Clears the server data (logout). Documents not sent yet are kept.
  Future<void> clearData() async {
    await db.put('data', null);
    data = null;
    notifyListeners();
  }
}
