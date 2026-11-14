import 'package:material_ui/material_ui.dart';

import '../core/money.dart';
import 'receipt_screen.dart';
import 'scope.dart';
import 'theme.dart';

/// End of day closing: totals of the day, count of the van stock and the cash handed over.
class ClosingScreen extends StatefulWidget {
  const ClosingScreen({super.key});
  @override
  State<ClosingScreen> createState() => _ClosingScreenState();
}

class _ClosingScreenState extends State<ClosingScreen> {
  final counted = <String, TextEditingController>{};
  final cash = TextEditingController();
  final note = TextEditingController();
  bool saving = false;

  TextEditingController countCtrl(String itemId, int expected) =>
      counted.putIfAbsent(itemId, () => TextEditingController(text: formatQty(expected)));

  Future<void> save() async {
    final repo = AppScope.repo(context);
    if (cash.text.trim().isEmpty) {
      showMessage(context, 'أدخل النقد المسلَّم', error: true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إقفال اليوم'),
        content: const Text('بعد الإقفال تبدأ عمليات يوم جديد. متابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إقفال')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => saving = true);
    final doc = await repo.saveClosing(
      {for (final e in counted.entries) e.key: toMilli(e.value.text)},
      toHalalas(cash.text),
      note: note.text.trim(),
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ReceiptScreen(doc: doc, autoPrint: true)));
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.repo(context);
    final s = repo.daySummary();
    Widget row(String label, int value, {bool bold = false, Color? color}) => ListTile(
          dense: true,
          title: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : null)),
          trailing: Text(money(value),
              style: TextStyle(fontSize: bold ? 18 : 15, fontWeight: bold ? FontWeight.bold : null, color: color)),
        );
    final handed = toHalalas(cash.text);
    final diff = handed - s.cashExpected;

    return Scaffold(
      appBar: AppBar(title: const Text('إقفال اليوم')),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Card(
          child: Column(children: [
            ListTile(
              title: Text('${s.invoices} فاتورة  ·  ${s.payments} تحصيل  ·  ${s.returnsCount} مرتجع  ·  ${s.visits} زيارة'),
            ),
            row('المبيعات', s.sales),
            row('منها آجل', s.credit),
            row('المرتجعات', s.returns),
            row('التحصيل نقداً', s.cashCollections),
            row('المقبوض تحويل / بطاقة', s.bank),
            row('المردود نقداً للعملاء', s.cashRefunds),
            row('النقد المتوقع في العهدة', s.cashExpected, bold: true, color: KaifColors.green),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('جرد مخزون السيارة', style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final i in repo.closingItems())
          Card(
            child: ListTile(
              title: Text(i.name),
              subtitle: Text('المتوقع: ${formatQty(repo.stock(i.id))} ${i.uom}'),
              trailing: SizedBox(
                width: 90,
                child: TextField(
                  controller: countCtrl(i.id, repo.stock(i.id)),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(labelText: 'المعدود', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: cash,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'النقد المسلَّم'),
                onChanged: (_) => setState(() {}),
              ),
              if (cash.text.trim().isNotEmpty && diff != 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${diff > 0 ? 'زيادة' : 'عجز'} في النقد: ${money(diff.abs())}',
                      style: const TextStyle(color: KaifColors.danger, fontWeight: FontWeight.bold)),
                ),
              const SizedBox(height: 12),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة')),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: saving ? null : save,
                icon: const Icon(Icons.lock_clock),
                label: const Text('إقفال اليوم وطباعة التقرير'),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
