import 'package:material_ui/material_ui.dart';

import '../core/money.dart';
import '../data/models.dart';
import 'receipt_screen.dart';
import 'scope.dart';
import 'theme.dart';

/// Collection of a customer's debt (سند قبض).
class PaymentScreen extends StatefulWidget {
  final String customerId;
  const PaymentScreen({super.key, required this.customerId});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final amount = TextEditingController();
  final note = TextEditingController();
  PayMethod method = PayMethod.cash;
  String invoice = '';
  bool saving = false;

  Future<void> save() async {
    final repo = AppScope.repo(context);
    final c = repo.data!.customer(widget.customerId)!;
    final a = toHalalas(amount.text);
    if (a <= 0) {
      showMessage(context, 'أدخل المبلغ المستلم', error: true);
      return;
    }
    setState(() => saving = true);
    final doc = await repo.savePayment(c, a, method, invoiceNumber: invoice, note: note.text.trim());
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ReceiptScreen(doc: doc, autoPrint: true)));
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.repo(context);
    final c = repo.data!.customer(widget.customerId)!;
    final open = repo.data!.openInvoices.where((i) => i.customer == c.id).toList();
    return Scaffold(
      appBar: AppBar(title: Text('تحصيل - ${c.name}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('الرصيد المستحق: ${money(repo.debt(c))}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: KaifColors.green)),
        const SizedBox(height: 16),
        TextField(
          controller: amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'المبلغ المستلم'),
        ),
        const SizedBox(height: 12),
        SegmentedButton<PayMethod>(
          segments: const [
            ButtonSegment(value: PayMethod.cash, label: Text('نقداً'), icon: Icon(Icons.money)),
            ButtonSegment(value: PayMethod.bank, label: Text('تحويل / بطاقة'), icon: Icon(Icons.credit_card)),
          ],
          selected: {method},
          onSelectionChanged: (s) => setState(() => method = s.first),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: invoice,
          decoration: const InputDecoration(labelText: 'عن الفاتورة'),
          items: [
            const DropdownMenuItem(value: '', child: Text('الأقدم أولاً (تلقائياً)')),
            for (final i in open) DropdownMenuItem(value: i.number, child: Text('${i.number}  (${money(i.left)})')),
          ],
          onChanged: (v) => setState(() => invoice = v ?? ''),
        ),
        const SizedBox(height: 12),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة')),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: saving ? null : save,
          icon: const Icon(Icons.print),
          label: const Text('حفظ وطباعة سند القبض'),
        ),
      ]),
    );
  }
}
