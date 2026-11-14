// Arabic amount in words for the printed documents. Same wording as the server function
// tafqit_sar (resources/sql/region/sa/tafqit.sql), so the device and the server print the same text.

const _ones = [
  '', 'واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'ثمانية', 'تسعة', 'عشرة', //
  'أحد عشر', 'اثنا عشر', 'ثلاثة عشر', 'أربعة عشر', 'خمسة عشر', 'ستة عشر', 'سبعة عشر', 'ثمانية عشر', 'تسعة عشر',
];
const _tens = ['', '', 'عشرون', 'ثلاثون', 'أربعون', 'خمسون', 'ستون', 'سبعون', 'ثمانون', 'تسعون'];
const _hundreds = ['', 'مائة', 'مائتان', 'ثلاثمائة', 'أربعمائة', 'خمسمائة', 'ستمائة', 'سبعمائة', 'ثمانمائة', 'تسعمائة'];

String _words999(int n) {
  if (n <= 0 || n > 999) return '';
  final parts = <String>[];
  final h = n ~/ 100, r = n % 100;
  if (h > 0) parts.add(_hundreds[h]);
  if (r > 0) {
    if (r < 20) {
      parts.add(_ones[r]);
    } else if (r % 10 == 0) {
      parts.add(_tens[r ~/ 10]);
    } else {
      parts.add('${_ones[r % 10]} و${_tens[r ~/ 10]}');
    }
  }
  return parts.join(' و');
}

String _scale(int n, String singular, String dual, String plural) {
  if (n == 1) return singular;
  if (n == 200) return 'مائتا $singular';
  if (n == 2) return dual;
  if (n >= 3 && n <= 10) return '${_words999(n)} $plural';
  return '${_words999(n)} $singular';
}

/// 1234 -> 'ألف ومائتان وأربعة وثلاثون'
String arabicWords(int n) {
  if (n == 0) return 'صفر';
  final parts = <String>[];
  final billions = (n ~/ 1000000000) % 1000, millions = (n ~/ 1000000) % 1000, thousands = (n ~/ 1000) % 1000;
  final rest = n % 1000;
  if (billions > 0) parts.add(_scale(billions, 'مليار', 'ملياران', 'مليارات'));
  if (millions > 0) parts.add(_scale(millions, 'مليون', 'مليونان', 'ملايين'));
  if (thousands > 0) parts.add(_scale(thousands, 'ألف', 'ألفان', 'آلاف'));
  if (rest > 0) parts.add(_words999(rest));
  return parts.join(' و');
}

/// [halalas] amount in halalas: 115050 -> 'فقط ألف ومائة وخمسون ريال سعودي وخمسون هللة لا غير'
String tafqitSar(int halalas) {
  final a = halalas.abs();
  final riyals = a ~/ 100, h = a % 100;
  final b = StringBuffer('فقط ');
  if (halalas < 0) b.write('سالب ');
  if (riyals > 0 || h == 0) b.write('${arabicWords(riyals)} ريال سعودي');
  if (h > 0) b.write('${riyals > 0 ? ' و' : ''}${arabicWords(h)} هللة');
  b.write(' لا غير');
  return b.toString();
}
