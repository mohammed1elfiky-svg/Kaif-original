import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/money.dart';
import '../core/zatca.dart';
import '../data/models.dart';

/// The printed document (80 or 58 mm thermal paper), the same layout as the server template
/// TaxInvoiceReceiptSa.jrxml. It is rendered to an image and sent to the printer as a raster,
/// so Arabic prints correctly on any ESC/POS printer.
class Receipt extends StatelessWidget {
  final Doc doc;
  final Company company;
  final int paperMm;
  const Receipt({super.key, required this.doc, required this.company, this.paperMm = 80});

  /// logical width; rendered with pixel ratio 2 -> 576 dots (80 mm) or 384 dots (58 mm) at 203 dpi
  double get width => paperMm == 58 ? 192 : 288;

  static final _date = DateFormat('yyyy-MM-dd HH:mm');

  String get qr => zatcaQr(
        sellerName: company.name,
        vatNumber: company.vat,
        timestamp: doc.date,
        totalWithVat: formatMoney(doc.totals.total, grouping: false),
        vatTotal: formatMoney(doc.totals.tax, grouping: false),
      );

  @override
  Widget build(BuildContext context) {
    final small = paperMm == 58;
    final base = TextStyle(fontSize: small ? 8 : 9.5, color: Colors.black, height: 1.3);
    final bold = base.copyWith(fontWeight: FontWeight.bold);
    final local = doc.date.toUtc().add(const Duration(hours: 3)); // Saudi time
    final kind = doc.kind;
    final hasLines = doc.hasLines;
    final simplified = doc.customerVat.isEmpty;
    final t = doc.totals;

    Widget row(String label, String value, {TextStyle? style}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(children: [
            Expanded(child: Text(label, style: style ?? base)),
            Text(value, style: style ?? base, textDirection: TextDirection.ltr),
          ]),
        );
    Widget dash() => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text('-' * 60, maxLines: 1, overflow: TextOverflow.clip, style: base),
        );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: width,
        color: Colors.white,
        padding: const EdgeInsets.all(4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Center(child: Image.asset('assets/logo.png', width: small ? 56 : 72, height: small ? 56 : 72)),
          Text(company.name, textAlign: TextAlign.center, style: bold.copyWith(fontSize: base.fontSize! + 2)),
          if (company.vat.isNotEmpty) Text('الرقم الضريبي: ${company.vat}', textAlign: TextAlign.center, style: base),
          if (company.cr.isNotEmpty) Text('السجل التجاري: ${company.cr}', textAlign: TextAlign.center, style: base),
          if (company.address.isNotEmpty) Text(company.address, textAlign: TextAlign.center, style: base),
          if (company.phone.isNotEmpty)
            Text(company.phone, textAlign: TextAlign.center, style: base, textDirection: TextDirection.ltr),
          dash(),
          Text(
            switch (kind) {
              DocKind.invoice => simplified ? 'فاتورة ضريبية مبسطة' : 'فاتورة ضريبية',
              DocKind.ret => simplified ? 'إشعار دائن لفاتورة مبسطة' : 'إشعار دائن',
              DocKind.closing => 'تقرير إقفال اليوم',
              _ => 'سند قبض',
            },
            textAlign: TextAlign.center,
            style: bold.copyWith(fontSize: base.fontSize! + 3),
          ),
          Text(
            switch (kind) {
              DocKind.invoice => simplified ? 'Simplified Tax Invoice' : 'Tax Invoice',
              DocKind.ret => 'Credit Note',
              DocKind.closing => 'End of Day Report',
              _ => 'Receipt Voucher',
            },
            textAlign: TextAlign.center,
            style: base,
          ),
          const SizedBox(height: 4),
          row('الرقم', doc.number, style: bold),
          row('التاريخ', _date.format(local)),
          row(kind == DocKind.closing ? 'الموزع' : 'العميل', doc.customerName, style: bold),
          if (doc.customerVat.isNotEmpty) row('الرقم الضريبي للعميل', doc.customerVat),
          if (kind == DocKind.ret) ...[
            if (doc.invoiceNumber.isNotEmpty) row('الفاتورة الأصلية', doc.invoiceNumber),
            row('سبب الإرجاع', doc.note),
          ],
          if (hasLines) ...[
            dash(),
            row('الصنف / الكمية × السعر', 'الإجمالي', style: bold),
            dash(),
            for (final l in doc.lines) ...[
              Text(l.itemName, style: bold),
              row(
                '${formatQty(l.qty)} ${l.uom} × ${formatMoney(l.price)}  (${formatQty(l.taxRate * 10)}%)',
                formatMoney(calcLine(qtyMilli: l.qty, price: l.price, rate: l.taxRate, taxIncluded: doc.taxIncluded)
                    .total),
              ),
            ],
            dash(),
            row('الإجمالي غير شامل الضريبة', '${formatMoney(t.net)} SAR'),
            row('ضريبة القيمة المضافة', '${formatMoney(t.tax)} SAR'),
            row('الإجمالي شامل الضريبة', '${formatMoney(t.total)} SAR', style: bold.copyWith(fontSize: base.fontSize! + 2)),
            if (kind == DocKind.invoice) ...[
              if (doc.paid > 0)
                row('المدفوع (${doc.method == PayMethod.cash ? 'نقداً' : 'تحويل'})', '${formatMoney(doc.paid)} SAR'),
              if (doc.credit > 0) row('المتبقي - آجل', '${formatMoney(doc.credit)} SAR', style: bold),
            ] else ...[
              if (doc.paid > 0) row('مردود نقداً للعميل', '${formatMoney(doc.paid)} SAR', style: bold),
              if (doc.paid < t.total) row('مخصوم من رصيد العميل', '${formatMoney(t.total - doc.paid)} SAR', style: bold),
            ],
            dash(),
            if (company.vat.isNotEmpty)
              Center(child: QrImageView(data: qr, size: small ? 110 : 140, padding: EdgeInsets.zero)),
          ] else if (kind == DocKind.closing) ...[
            dash(),
            row('عدد الفواتير / التحصيل / المرتجع',
                '${doc.summary['invoices'] ?? 0} / ${doc.summary['payments'] ?? 0} / ${doc.summary['returnsCount'] ?? 0}'),
            row('عدد الزيارات', '${doc.summary['visits'] ?? 0}'),
            row('المبيعات', formatMoney(doc.summary['sales'] ?? 0)),
            row('منها آجل', formatMoney(doc.summary['credit'] ?? 0)),
            row('المرتجعات', formatMoney(doc.summary['returns'] ?? 0)),
            row('مبيعات نقدية', formatMoney(doc.summary['cashSales'] ?? 0)),
            row('تحصيل نقدي', formatMoney(doc.summary['cashCollections'] ?? 0)),
            row('مردود نقداً', formatMoney(doc.summary['cashRefunds'] ?? 0)),
            row('تحويل / بطاقة', formatMoney(doc.summary['bank'] ?? 0)),
            dash(),
            row('النقد المتوقع', '${formatMoney(doc.summary['cashExpected'] ?? 0)} SAR', style: bold),
            row('النقد المسلَّم', '${formatMoney(doc.summary['cashHanded'] ?? 0)} SAR', style: bold),
            if ((doc.summary['cashHanded'] ?? 0) != (doc.summary['cashExpected'] ?? 0))
              row('الفرق', formatMoney((doc.summary['cashHanded'] ?? 0) - (doc.summary['cashExpected'] ?? 0)),
                  style: bold),
            dash(),
            row('الصنف / المتوقع - المعدود', 'الفرق', style: bold),
            for (final l in doc.closingLines) ...[
              Text(l.itemName, style: base),
              row('${formatQty(l.expected)} - ${formatQty(l.counted)} ${l.uom}',
                  l.difference == 0 ? '✓' : formatQty(l.difference),
                  style: l.difference == 0 ? base : bold),
            ],
            if (doc.note.isNotEmpty) ...[dash(), row('ملاحظة', doc.note)],
            const SizedBox(height: 16),
            row('توقيع الموزع', '..................'),
            const SizedBox(height: 12),
            row('توقيع المستلم', '..................'),
          ] else ...[
            dash(),
            row('المبلغ المستلم', '${formatMoney(doc.paid)} SAR', style: bold.copyWith(fontSize: base.fontSize! + 2)),
            row('طريقة الدفع', doc.method == PayMethod.cash ? 'نقداً' : 'تحويل / بطاقة'),
            if (doc.invoiceNumber.isNotEmpty) row('عن الفاتورة', doc.invoiceNumber),
            if (doc.note.isNotEmpty) row('ملاحظة', doc.note),
            const SizedBox(height: 16),
            row('توقيع المستلم', '..................'),
          ],
          const SizedBox(height: 6),
          if (kind != DocKind.closing) Text('شكراً لتعاملكم معنا', textAlign: TextAlign.center, style: bold),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }
}
