import '../core/money.dart';

/// Data downloaded from the server (Distribution.getData).

class Distributor {
  final String id, name, prefix, location;

  /// last document numbers received by the server, by kind (the app continues after them)
  final Map<DocKind, String> lastNumbers;
  Distributor(this.id, this.name, this.prefix, this.location, [this.lastNumbers = const {}]);
  factory Distributor.fromJson(Map<String, dynamic> j) => Distributor(
        _s(j['id']),
        _s(j['name']),
        _s(j['prefix']),
        _s(j['location']),
        {
          DocKind.invoice: _s(j['lastInvoice']),
          DocKind.payment: _s(j['lastPayment']),
          DocKind.ret: _s(j['lastReturn']),
          DocKind.closing: _s(j['lastClosing']),
        },
      );
}

/// sequence number at the end of a document number: 'D01-R-000123' -> 123
int numberSequence(String number) => int.tryParse(RegExp(r'(\d+)$').firstMatch(number)?.group(1) ?? '') ?? 0;

class Company {
  final String name, vat, cr, address, phone;
  Company(this.name, this.vat, this.cr, this.address, this.phone);
  factory Company.fromJson(Map<String, dynamic> j) =>
      Company(_s(j['name']), _s(j['vat']), _s(j['cr']), _s(j['address']), _s(j['phone']));
}

class Customer {
  final String id, name, vat, address, phone, priceType;
  final double? latitude, longitude;
  final int? paymentDays;
  final int? creditLimit; // halalas, null = no limit
  final int? maxOverdueDays; // null = no check
  final int debt; // halalas, as of download
  final int overdueDays; // oldest overdue debt, as of download
  final List<int> visitDays; // ISO weekdays: Monday = 1 ... Sunday = 7
  final int? visitOrder;

  Customer({
    required this.id,
    required this.name,
    this.vat = '',
    this.address = '',
    this.phone = '',
    this.priceType = '',
    this.latitude,
    this.longitude,
    this.paymentDays,
    this.creditLimit,
    this.maxOverdueDays,
    this.debt = 0,
    this.overdueDays = 0,
    this.visitDays = const [],
    this.visitOrder,
  });

  bool visitOn(DateTime day) => visitDays.contains(day.weekday);

  bool get hasVat => vat.isNotEmpty;

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: _s(j['id']),
        name: _s(j['name']),
        vat: _s(j['vat']),
        address: _s(j['address']),
        phone: _s(j['phone']),
        priceType: _s(j['priceType']),
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        paymentDays: (j['paymentDays'] as num?)?.toInt(),
        creditLimit: j['creditLimit'] == null ? null : toHalalas(j['creditLimit']),
        maxOverdueDays: (j['maxOverdueDays'] as num?)?.toInt(),
        debt: toHalalas(j['debt']),
        overdueDays: (j['overdueDays'] as num?)?.toInt() ?? 0,
        visitDays: _s(j['visitDays']).split(',').map((e) => int.tryParse(e.trim())).whereType<int>().toList(),
        visitOrder: (j['visitOrder'] as num?)?.toInt(),
      );
}

class OpenInvoice {
  final String customer, number;
  final DateTime? date, due;
  final int amount, left;
  OpenInvoice(this.customer, this.number, this.date, this.due, this.amount, this.left);
  factory OpenInvoice.fromJson(Map<String, dynamic> j) => OpenInvoice(_s(j['customer']), _s(j['number']),
      _d(j['date']), _d(j['due']), toHalalas(j['amount']), toHalalas(j['left']));
}

class Item {
  final String id, name, barcode, uom;
  final int taxRate; // hundredths of a percent
  final int onHand; // thousandths, van stock as of download
  final String packUom; // sales package (carton), empty when none
  final int packRatio; // base units in a package, thousandths (24 pieces = 24000)
  Item(this.id, this.name, this.barcode, this.uom, this.taxRate, this.onHand, [this.packUom = '', this.packRatio = 0]);

  bool get hasPack => packRatio > 1000 && packUom.isNotEmpty;

  factory Item.fromJson(Map<String, dynamic> j) => Item(_s(j['id']), _s(j['name']), _s(j['barcode']),
      _s(j['uom']), toHalalas(j['tax']), toMilli(j['onHand']), _s(j['packUom']), toMilli(j['packRatio']));
}

/// 30 pieces with cartons of 24 -> "1 كرتون + 6 حبة"
String formatPacks(int qtyMilli, Item item) {
  if (!item.hasPack) return '${formatQty(qtyMilli)} ${item.uom}';
  final packs = qtyMilli ~/ item.packRatio;
  final rest = qtyMilli - packs * item.packRatio;
  return [
    if (packs > 0) '$packs ${item.packUom}',
    if (rest > 0 || packs == 0) '${formatQty(rest)} ${item.uom}',
  ].join(' + ');
}

class Price {
  final String priceType, item;
  final bool taxIncluded;
  final int price; // halalas
  Price(this.priceType, this.item, this.taxIncluded, this.price);
  factory Price.fromJson(Map<String, dynamic> j) =>
      Price(_s(j['priceType']), _s(j['item']), j['taxIncluded'] == true, toHalalas(j['price']));
}

class ServerData {
  final Distributor distributor;
  final Company company;
  final List<Customer> customers;
  final List<OpenInvoice> openInvoices;
  final List<Item> items;
  final List<Price> prices;

  ServerData(this.distributor, this.company, this.customers, this.openInvoices, this.items, this.prices);

  factory ServerData.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String k) =>
        ((j[k] as List?) ?? const []).cast<Map<String, dynamic>>();
    final d = list('distributor');
    final c = list('company');
    return ServerData(
      d.isEmpty ? Distributor('', '', 'D', '') : Distributor.fromJson(d.first),
      c.isEmpty ? Company('', '', '', '', '') : Company.fromJson(c.first),
      list('customers').map(Customer.fromJson).toList(),
      list('openInvoices').map(OpenInvoice.fromJson).toList(),
      list('items').map(Item.fromJson).toList(),
      list('prices').map(Price.fromJson).toList(),
    );
  }

  Customer? customer(String id) => customers.where((c) => c.id == id).firstOrNull;
  Item? item(String id) => items.where((i) => i.id == id).firstOrNull;

  Price? price(String priceType, String item) =>
      prices.where((p) => p.priceType == priceType && p.item == item).firstOrNull;
}

/// Documents created on the device.

enum DocKind { invoice, payment, ret, visit, closing }

enum DocStatus { pending, sent, error }

enum PayMethod { cash, bank }

class SaleLine {
  final String itemId, itemName, uom;
  final int qty; // thousandths
  final int price; // halalas
  final int taxRate;
  SaleLine(this.itemId, this.itemName, this.uom, this.qty, this.price, this.taxRate);

  Map<String, dynamic> toJson() =>
      {'item': itemId, 'name': itemName, 'uom': uom, 'qty': qty, 'price': price, 'rate': taxRate};
  factory SaleLine.fromJson(Map<String, dynamic> j) =>
      SaleLine(j['item'], j['name'], j['uom'] ?? '', j['qty'], j['price'], j['rate']);
}

class Totals {
  final int net, tax, total;
  const Totals(this.net, this.tax, this.total);
}

class Doc {
  final String id; // UUID, idempotency key on the server
  final DocKind kind;
  final String number;
  final DateTime date; // UTC
  final String customerId, customerName, customerVat;
  final bool taxIncluded;
  final List<SaleLine> lines;
  final int paid; // invoice: paid immediately; payment: amount
  final PayMethod method;
  final String invoiceNumber; // payment: invoice it pays (optional)
  final String note; // return: the reason
  final double? latitude, longitude;
  final String result; // visit: sale, payment, return, closed, no_need, other
  final List<ClosingLine> closingLines;
  final Map<String, int> summary; // closing: amounts of the day (halalas)
  DocStatus status;
  String error;
  bool inSnapshot; // already reflected in the last downloaded server data

  Doc({
    required this.id,
    required this.kind,
    required this.number,
    required this.date,
    required this.customerId,
    required this.customerName,
    this.customerVat = '',
    this.taxIncluded = false,
    this.lines = const [],
    this.paid = 0,
    this.method = PayMethod.cash,
    this.invoiceNumber = '',
    this.note = '',
    this.latitude,
    this.longitude,
    this.result = '',
    this.closingLines = const [],
    this.summary = const {},
    this.status = DocStatus.pending,
    this.error = '',
    this.inSnapshot = false,
  });

  Totals get totals {
    var tax = 0, total = 0;
    for (final l in lines) {
      final a = calcLine(qtyMilli: l.qty, price: l.price, rate: l.taxRate, taxIncluded: taxIncluded);
      tax += a.tax;
      total += a.total;
    }
    return Totals(total - tax, tax, total);
  }

  bool get hasLines => kind == DocKind.invoice || kind == DocKind.ret;

  /// unpaid (credit) part of an invoice
  int get credit => kind == DocKind.invoice ? totals.total - paid : 0;

  /// change of the customer's debt: a credit sale increases it, a collection and a return
  /// (except the part refunded in cash) decrease it
  int get debtEffect => switch (kind) {
        DocKind.invoice => totals.total - paid,
        DocKind.payment => -paid,
        DocKind.ret => -(totals.total - paid),
        _ => 0,
      };

  /// change of the van stock of the item: sold goods leave the van, returned goods come back
  int stockEffect(String itemId) {
    if (!hasLines) return 0;
    var q = 0;
    for (final l in lines.where((l) => l.itemId == itemId)) {
      q += l.qty;
    }
    return kind == DocKind.invoice ? -q : q;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'number': number,
        'date': date.toUtc().toIso8601String(),
        'customerId': customerId,
        'customerName': customerName,
        'customerVat': customerVat,
        'taxIncluded': taxIncluded,
        'lines': lines.map((l) => l.toJson()).toList(),
        'paid': paid,
        'method': method.name,
        'invoiceNumber': invoiceNumber,
        'note': note,
        'latitude': latitude,
        'longitude': longitude,
        'result': result,
        'closingLines': closingLines.map((l) => l.toJson()).toList(),
        'summary': summary,
      };

  factory Doc.fromJson(Map<String, dynamic> j,
          {DocStatus status = DocStatus.pending, String error = '', bool inSnapshot = false}) =>
      Doc(
        id: j['id'],
        kind: DocKind.values.byName(j['kind']),
        number: j['number'],
        date: DateTime.parse(j['date']),
        customerId: j['customerId'],
        customerName: j['customerName'] ?? '',
        customerVat: j['customerVat'] ?? '',
        taxIncluded: j['taxIncluded'] == true,
        lines: ((j['lines'] as List?) ?? const []).map((e) => SaleLine.fromJson(e)).toList(),
        paid: j['paid'] ?? 0,
        method: PayMethod.values.byName(j['method'] ?? 'cash'),
        invoiceNumber: j['invoiceNumber'] ?? '',
        note: j['note'] ?? '',
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        result: j['result'] ?? '',
        closingLines: ((j['closingLines'] as List?) ?? const []).map((e) => ClosingLine.fromJson(e)).toList(),
        summary: ((j['summary'] as Map?) ?? const {}).map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        status: status,
        error: error,
        inSnapshot: inSnapshot,
      );

  /// The document in the format of Distribution.upload. Dates are sent in Saudi local time
  /// (UTC+3, no daylight saving), as the server keeps document dates in local time.
  Map<String, dynamic> toUploadJson() {
    final d = date.toUtc().add(const Duration(hours: 3)).toIso8601String().substring(0, 19);
    String m(int v) => formatMoney(v, grouping: false);
    List<Map<String, dynamic>> uploadLines() => lines
        .map((l) => {'item': l.itemId, 'quantity': formatQty(l.qty), 'price': m(l.price)})
        .toList();
    return switch (kind) {
      DocKind.invoice => {
          'id': id,
          'number': number,
          'date': d,
          'customer': customerId,
          'taxIncluded': taxIncluded,
          'paid': m(paid),
          'method': method.name,
          'note': note,
          'lines': uploadLines(),
        },
      DocKind.payment => {
          'id': id,
          'number': number,
          'date': d,
          'customer': customerId,
          'amount': m(paid),
          'method': method.name,
          'invoice': invoiceNumber,
          'note': note,
        },
      DocKind.ret => {
          'id': id,
          'number': number,
          'date': d,
          'customer': customerId,
          'taxIncluded': taxIncluded,
          'refund': m(paid),
          'invoice': invoiceNumber,
          'reason': note,
          'lines': uploadLines(),
        },
      DocKind.visit => {
          'id': id,
          'date': d,
          'customer': customerId,
          'latitude': latitude,
          'longitude': longitude,
          'result': result,
          'note': note,
        },
      DocKind.closing => {
          'id': id,
          'number': number,
          'date': d,
          'sales': m(summary['sales'] ?? 0),
          'credit': m(summary['credit'] ?? 0),
          'returns': m(summary['returns'] ?? 0),
          'bank': m(summary['bank'] ?? 0),
          'cashExpected': m(summary['cashExpected'] ?? 0),
          'cashHanded': m(summary['cashHanded'] ?? 0),
          'note': note,
          'lines': closingLines
              .map((l) => {'item': l.itemId, 'expected': formatQty(l.expected), 'counted': formatQty(l.counted)})
              .toList(),
        },
    };
  }
}

/// end of day closing: the van stock expected by the app and counted by the distributor
class ClosingLine {
  final String itemId, itemName, uom;
  final int expected, counted; // thousandths
  ClosingLine(this.itemId, this.itemName, this.uom, this.expected, this.counted);
  int get difference => counted - expected;

  Map<String, dynamic> toJson() => {'item': itemId, 'name': itemName, 'uom': uom, 'expected': expected, 'counted': counted};
  factory ClosingLine.fromJson(Map<String, dynamic> j) =>
      ClosingLine(j['item'], j['name'] ?? '', j['uom'] ?? '', j['expected'] ?? 0, j['counted'] ?? 0);
}

/// what happened at the customer during a visit
const visitResults = {
  'sale': 'بيع',
  'payment': 'تحصيل',
  'return': 'مرتجع',
  'closed': 'المحل مغلق',
  'no_need': 'لا يحتاج بضاعة',
  'no_money': 'لا يوجد سيولة',
  'other': 'أخرى',
};

/// reasons of customer returns
const returnReasons = ['منتهي الصلاحية', 'تالف', 'بضاعة غير مباعة', 'خطأ في الطلب', 'أخرى'];

String _s(Object? v) => v == null ? '' : v.toString();

DateTime? _d(Object? v) => v == null ? null : DateTime.tryParse(v.toString());
