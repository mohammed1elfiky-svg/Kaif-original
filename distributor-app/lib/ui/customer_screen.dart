import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import 'payment_screen.dart';
import 'sale_screen.dart';
import 'scope.dart';
import 'theme.dart';

class CustomerScreen extends StatelessWidget {
  final String customerId;
  const CustomerScreen({super.key, required this.customerId});

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.repo(context);
    final c = repo.data!.customer(customerId)!;
    final debt = repo.debt(c);
    final available = repo.availableCredit(c);
    final overdue = c.maxOverdueDays != null && c.overdueDays > c.maxOverdueDays!;
    final open = repo.data!.openInvoices.where((i) => i.customer == c.id).toList();
    final fmt = DateFormat('yyyy-MM-dd');
    Widget info(String label, String value, {Color? color}) => ListTile(
          dense: true,
          title: Text(label),
          trailing: Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        );

    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
      body: ListView(children: [
        Card(
          child: Column(children: [
            if (c.phone.isNotEmpty) info('الهاتف', c.phone),
            if (c.address.isNotEmpty) ListTile(dense: true, title: const Text('العنوان'), subtitle: Text(c.address)),
            if (c.vat.isNotEmpty) info('الرقم الضريبي', c.vat),
            info('الرصيد المستحق', money(debt), color: debt > 0 ? KaifColors.danger : null),
            if (c.creditLimit != null) info('الحد الائتماني', money(c.creditLimit!)),
            if (available != null) info('المتاح للبيع الآجل', money(available), color: available <= 0 ? KaifColors.danger : null),
            if (c.paymentDays != null) info('مدة السداد', '${c.paymentDays} يوم'),
            if (overdue)
              ListTile(
                leading: const Icon(Icons.warning_amber, color: KaifColors.danger),
                title: Text('ديون متأخرة ${c.overdueDays} يوماً - البيع نقداً فقط',
                    style: const TextStyle(color: KaifColors.danger)),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('بيع'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SaleScreen(customerId: c.id))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.payments_outlined),
                label: const Text('تحصيل'),
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PaymentScreen(customerId: c.id))),
              ),
            ),
          ]),
        ),
        if (open.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('الفواتير غير المسددة (حتى آخر مزامنة)', style: Theme.of(context).textTheme.titleSmall),
          ),
        for (final i in open)
          Card(
            child: ListTile(
              title: Text(i.number),
              subtitle: Text([
                if (i.date != null) fmt.format(i.date!),
                if (i.due != null) 'الاستحقاق ${fmt.format(i.due!)}',
              ].join('  ·  ')),
              trailing: Text(money(i.left)),
            ),
          ),
      ]),
    );
  }
}
