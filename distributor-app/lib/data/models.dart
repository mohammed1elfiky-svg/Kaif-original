import '../core/money.dart';

/// Data downloaded from the server (Distribution.getData).

class Distributor {
  final String id, name, prefix, location;
  Distributor(this.id, this.name, this.prefix, this.location);
  factory Distributor.fromJson(Map<String, dynamic> j) =>
      Distributor(_s(j['id']), _s(j['name']), _s(j['prefix']), _s(j['location']));
}

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
  });

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
  Item(this.id, this.name, this.barcode, this.uom, this.taxRate, this.onHand);
  factory Item.fromJson(Map<String, dynamic> j) => Item(_s(j['id']), _s(j['name']), _s(j['barcode']),
      _s(j['uom']), toHalalas(j['tax']), toMilli(j['onHand']));
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

enum DocKind { invoice, payment }

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
  final String note;
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

  /// unpaid (credit) part of an invoice
  int get credit => kind == DocKind.invoice ? totals.total - paid : 0;

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
        status: status,
        error: error,
        inSnapshot: inSnapshot,
      );

  /// The document in the format of Distribution.upload. The date is sent in Saudi local time
  /// (UTC+3, no daylight saving), as the server keeps invoice dates in local time.
  Map<String, dynamic> toUploadJson() {
    final local = date.toUtc().add(const Duration(hours: 3));
    final d = local.toIso8601String().substring(0, 19);
    if (kind == DocKind.invoice) {
      return {
        'id': id,
        'number': number,
        'date': d,
        'customer': customerId,
        'taxIncluded': taxIncluded,
        'paid': formatMoney(paid, grouping: false),
        'method': method.name,
        'note': note,
        'lines': lines
            .map((l) => {
                  'item': l.itemId,
                  'quantity': formatQty(l.qty),
                  'price': formatMoney(l.price, grouping: false),
                })
            .toList(),
      };
    }
    return {
      'id': id,
      'number': number,
      'date': d,
      'customer': customerId,
      'amount': formatMoney(paid, grouping: false),
      'method': method.name,
      'invoice': invoiceNumber,
      'note': note,
    };
  }
}

String _s(Object? v) => v == null ? '' : v.toString();

DateTime? _d(Object? v) => v == null ? null : DateTime.tryParse(v.toString());
