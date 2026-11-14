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

/// Totals of the distributor's day: the documents made since the last closing.
class DaySummary {
  final int sales; // invoices, with tax
  final int credit; // unpaid part of the invoices
  final int cashSales, bankSales; // paid immediately on the invoices
  final int cashCollections, bankCollections;
  final int returns; // credit notes, with tax
  final int cashRefunds;
  final int invoices, payments, returnsCount, visits;

  const DaySummary({
    this.sales = 0,
    this.credit = 0,
    this.cashSales = 0,
    this.bankSales = 0,
    this.cashCollections = 0,
    this.bankCollections = 0,
    this.returns = 0,
    this.cashRefunds = 0,
    this.invoices = 0,
    this.payments = 0,
    this.returnsCount = 0,
    this.visits = 0,
  });

  /// cash the distributor must hand over
  int get cashExpected => cashSales + cashCollections - cashRefunds;
  int get bank => bankSales + bankCollections;
}

typedef LocationProvider = Future<({double latitude, double longitude})?> Function();

/// State of the app: server data + documents made on the device, and the van stock and
/// customer debts adjusted by the documents that are not in the server data yet.
class Repository extends ChangeNotifier {
  final LocalDb db;
  Api? api;

  /// current GPS position for the visits; null result when it is not available
  LocationProvider? locate;

  /// clock, replaceable in tests
  DateTime Function() now = () => DateTime.now().toUtc();

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

  /// documents to show in the documents list (visits are not printed)
  Iterable<Doc> get printableDocs => docs.where((d) => d.kind != DocKind.visit);

  /// van stock: as of download, with the sales and returns made after it
  int stock(String itemId) {
    var v = data?.item(itemId)?.onHand ?? 0;
    for (final d in _local) {
      v += d.stockEffect(itemId);
    }
    return v;
  }

  /// customer debt: as of download, with the credit sales, returns and collections made after it
  int debt(Customer c) {
    var v = c.debt;
    for (final d in _local.where((d) => d.customerId == c.id)) {
      v += d.debtEffect;
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

  /// invoices of the customer that a return or a collection can refer to: the unpaid ones from the
  /// server and the ones made on the device
  List<String> customerInvoices(Customer c) => {
        ...docs.where((d) => d.kind == DocKind.invoice && d.customerId == c.id).map((d) => d.number),
        ...?data?.openInvoices.where((i) => i.customer == c.id).map((i) => i.number),
      }.toList();

  // ---------- route ----------

  /// Saudi local date of a moment
  static DateTime saudiDay(DateTime t) {
    final l = t.toUtc().add(const Duration(hours: 3));
    return DateTime.utc(l.year, l.month, l.day);
  }

  DateTime get today => saudiDay(now());

  /// customers to visit today, in the route order
  List<Customer> todayRoute() {
    int order(Customer c) => c.visitOrder ?? 1 << 30;
    return (data?.customers ?? []).where((c) => c.visitOn(today)).toList()
      ..sort((a, b) {
        final o = order(a).compareTo(order(b));
        return o != 0 ? o : a.name.compareTo(b.name);
      });
  }

  bool visitedToday(Customer c) =>
      docs.any((d) => d.customerId == c.id && d.kind != DocKind.closing && saudiDay(d.date) == today);

  // ---------- documents ----------

  Future<Doc> _save(DocKind kind, Doc Function(String id, String number, DateTime date) build) async {
    final doc = await db.insertDoc((number) => build(const Uuid().v4(), number, now()), data!.distributor.prefix, kind);
    docs.insert(0, doc);
    notifyListeners();
    return doc;
  }

  Future<Doc> saveInvoice(Customer c, List<SaleLine> lines, bool taxIncluded, int paid, PayMethod method,
      {String note = ''}) async {
    final doc = await _save(
        DocKind.invoice,
        (id, number, date) => Doc(
              id: id,
              kind: DocKind.invoice,
              number: number,
              date: date,
              customerId: c.id,
              customerName: c.name,
              customerVat: c.vat,
              taxIncluded: taxIncluded,
              lines: lines,
              paid: paid,
              method: method,
              note: note,
            ));
    await logVisit(c, 'sale');
    return doc;
  }

  Future<Doc> savePayment(Customer c, int amount, PayMethod method, {String invoiceNumber = '', String note = ''}) async {
    final doc = await _save(
        DocKind.payment,
        (id, number, date) => Doc(
              id: id,
              kind: DocKind.payment,
              number: number,
              date: date,
              customerId: c.id,
              customerName: c.name,
              customerVat: c.vat,
              paid: amount,
              method: method,
              invoiceNumber: invoiceNumber,
              note: note,
            ));
    await logVisit(c, 'payment');
    return doc;
  }

  /// Customer return (credit note): the goods come back to the van stock; [refund] is paid back
  /// in cash, the rest decreases the customer's debt.
  Future<Doc> saveReturn(Customer c, List<SaleLine> lines, bool taxIncluded, int refund,
      {String invoiceNumber = '', required String reason}) async {
    final doc = await _save(
        DocKind.ret,
        (id, number, date) => Doc(
              id: id,
              kind: DocKind.ret,
              number: number,
              date: date,
              customerId: c.id,
              customerName: c.name,
              customerVat: c.vat,
              taxIncluded: taxIncluded,
              lines: lines,
              paid: refund,
              method: PayMethod.cash,
              invoiceNumber: invoiceNumber,
              note: reason,
            ));
    await logVisit(c, 'return');
    return doc;
  }

  /// Visit of a customer with the GPS position (when available). Visits with a sale, a collection
  /// or a return are logged automatically.
  Future<Doc> logVisit(Customer c, String result, {String note = ''}) async {
    ({double latitude, double longitude})? pos;
    try {
      pos = await locate?.call();
    } catch (_) {
      pos = null;
    }
    return _save(
        DocKind.visit,
        (id, number, date) => Doc(
              id: id,
              kind: DocKind.visit,
              number: number,
              date: date,
              customerId: c.id,
              customerName: c.name,
              latitude: pos?.latitude,
              longitude: pos?.longitude,
              result: result,
              note: note,
            ));
  }

  Doc? get lastClosing => docs.where((d) => d.kind == DocKind.closing).firstOrNull;

  /// documents of the day: made after the last closing
  Iterable<Doc> get dayDocs {
    final from = lastClosing?.date;
    return docs.where((d) => d.kind != DocKind.closing && (from == null || d.date.isAfter(from)));
  }

  DaySummary daySummary() {
    var sales = 0, credit = 0, cashSales = 0, bankSales = 0, cashColl = 0, bankColl = 0, returns = 0, refunds = 0;
    var nInv = 0, nPay = 0, nRet = 0, nVis = 0;
    for (final d in dayDocs) {
      switch (d.kind) {
        case DocKind.invoice:
          nInv++;
          sales += d.totals.total;
          credit += d.credit;
          if (d.method == PayMethod.cash) {
            cashSales += d.paid;
          } else {
            bankSales += d.paid;
          }
        case DocKind.payment:
          nPay++;
          if (d.method == PayMethod.cash) {
            cashColl += d.paid;
          } else {
            bankColl += d.paid;
          }
        case DocKind.ret:
          nRet++;
          returns += d.totals.total;
          refunds += d.paid;
        case DocKind.visit:
          nVis++;
        case DocKind.closing:
          break;
      }
    }
    return DaySummary(
      sales: sales,
      credit: credit,
      cashSales: cashSales,
      bankSales: bankSales,
      cashCollections: cashColl,
      bankCollections: bankColl,
      returns: returns,
      cashRefunds: refunds,
      invoices: nInv,
      payments: nPay,
      returnsCount: nRet,
      visits: nVis,
    );
  }

  /// items expected in the van for the stock count of the closing
  List<Item> closingItems() =>
      (data?.items ?? []).where((i) => i.onHand != 0 || stock(i.id) != 0).toList()..sort((a, b) => a.name.compareTo(b.name));

  /// End of day closing: the counted van stock ([counted] by item id, thousandths) and the cash handed over.
  Future<Doc> saveClosing(Map<String, int> counted, int cashHanded, {String note = ''}) {
    final s = daySummary();
    final lines = [
      for (final i in closingItems()) ClosingLine(i.id, i.name, i.uom, stock(i.id), counted[i.id] ?? stock(i.id)),
    ];
    final summary = {
      'sales': s.sales,
      'credit': s.credit,
      'returns': s.returns,
      'cashSales': s.cashSales,
      'cashCollections': s.cashCollections,
      'cashRefunds': s.cashRefunds,
      'bank': s.bank,
      'cashExpected': s.cashExpected,
      'cashHanded': cashHanded,
      'invoices': s.invoices,
      'payments': s.payments,
      'returnsCount': s.returnsCount,
      'visits': s.visits,
    };
    return _save(
        DocKind.closing,
        (id, number, date) => Doc(
              id: id,
              kind: DocKind.closing,
              number: number,
              date: date,
              customerId: '',
              customerName: data!.distributor.name,
              closingLines: lines,
              summary: summary,
              note: note,
            ));
  }

  // ---------- synchronization ----------

  static const _uploadKeys = {
    DocKind.invoice: 'invoices',
    DocKind.payment: 'payments',
    DocKind.ret: 'returns',
    DocKind.visit: 'visits',
    DocKind.closing: 'closings',
  };

  /// Uploads the documents not received by the server yet, then downloads fresh data.
  Future<void> sync() async {
    if (api == null || syncing) return;
    syncing = true;
    lastSyncError = null;
    notifyListeners();
    try {
      final toSend = docs.where((d) => d.status != DocStatus.sent).toList().reversed.toList();
      if (toSend.isNotEmpty) {
        final result = await api!.upload({
          for (final e in _uploadKeys.entries)
            e.value: toSend.where((d) => d.kind == e.key).map((d) => d.toUploadJson()).toList(),
        });
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
    for (final e in fresh.distributor.lastNumbers.entries) {
      await db.ensureCounter(e.key, numberSequence(e.value));
    }
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
