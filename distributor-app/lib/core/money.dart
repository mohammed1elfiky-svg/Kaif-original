// Money is kept in halalas (1/100 SAR) and quantities in thousandths, so that the totals
// calculated on the device are exactly the totals the server calculates for the same invoice
// (Invoicing MetaTax: untaxed = qty * price, tax = rate / (100 [+ rate if included]) * untaxed,
// each rounded half up to 2 decimals).

int roundDiv(int numerator, int denominator) {
  final negative = (numerator < 0) != (denominator < 0);
  final n = numerator.abs(), d = denominator.abs();
  final q = (n * 2 + d) ~/ (d * 2);
  return negative ? -q : q;
}

/// Parses a decimal number (num or string from JSON) into hundredths.
int toHalalas(Object? v) => _toScaled(v, 2);

/// Parses a quantity into thousandths.
int toMilli(Object? v) => _toScaled(v, 3);

int _toScaled(Object? v, int scale) {
  if (v == null) return 0;
  final s = v is String ? v.trim() : v.toString();
  if (s.isEmpty) return 0;
  final negative = s.startsWith('-');
  final body = negative ? s.substring(1) : s;
  final parts = body.split('.');
  final whole = int.parse(parts[0].isEmpty ? '0' : parts[0]);
  var frac = parts.length > 1 ? parts[1] : '';
  var result = whole;
  for (var i = 0; i < scale; i++) {
    result = result * 10 + (i < frac.length ? int.parse(frac[i]) : 0);
  }
  // round half up on the next digit
  if (frac.length > scale && int.parse(frac[scale]) >= 5) result += 1;
  return negative ? -result : result;
}

/// 1234567 -> "12,345.67"; [grouping] false -> "12345.67" (for the QR code and the API).
String formatMoney(int halalas, {bool grouping = true}) {
  final negative = halalas < 0;
  final a = halalas.abs();
  var whole = (a ~/ 100).toString();
  final frac = (a % 100).toString().padLeft(2, '0');
  if (grouping) {
    final b = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
      b.write(whole[i]);
    }
    whole = b.toString();
  }
  return '${negative ? '-' : ''}$whole.$frac';
}

/// 2500 -> "2.5", 3000 -> "3"
String formatQty(int milli) {
  final whole = milli ~/ 1000;
  final frac = (milli.abs() % 1000).toString().padLeft(3, '0').replaceAll(RegExp(r'0+$'), '');
  return frac.isEmpty ? '$whole' : '$whole.$frac';
}

class LineAmounts {
  final int untaxed; // as the server's untaxedAmount (includes tax when prices include tax)
  final int tax;
  final int total; // with tax
  int get net => total - tax;
  const LineAmounts(this.untaxed, this.tax, this.total);
}

/// [rate] tax rate in hundredths of a percent (15% = 1500).
LineAmounts calcLine({required int qtyMilli, required int price, required int rate, required bool taxIncluded}) {
  final untaxed = roundDiv(qtyMilli * price, 1000);
  final tax = rate == 0 ? 0 : roundDiv(untaxed * rate, 10000 + (taxIncluded ? rate : 0));
  final total = taxIncluded ? untaxed : untaxed + tax;
  return LineAmounts(untaxed, tax, total);
}
