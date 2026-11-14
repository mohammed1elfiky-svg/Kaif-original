import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import 'payment_screen.dart';
import 'return_screen.dart';
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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
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
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.assignment_return_outlined),
                label: const Text('مرتجع'),
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReturnScreen(customerId: c.id))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.location_on_outlined),
                label: const Text('زيارة بدون بيع'),
                onPressed: () => _logVisit(context, c),
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

/// Visit without a sale: the reason, with the GPS position.
Future<void> _logVisit(BuildContext context, Customer c) async {
  final repo = AppScope.repo(context);
  final note = TextEditingController();
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('نتيجة الزيارة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة')),
          ),
          for (final e in visitResults.entries.where((e) => !const ['sale', 'payment', 'return'].contains(e.key)))
            ListTile(title: Text(e.value), onTap: () => Navigator.pop(ctx, e.key)),
        ]),
      ),
    ),
  );
  if (result == null || !context.mounted) return;
  await repo.logVisit(c, result, note: note.text.trim());
  if (context.mounted) showMessage(context, 'تم تسجيل الزيارة');
}
