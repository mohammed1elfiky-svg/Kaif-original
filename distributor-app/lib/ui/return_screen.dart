import 'package:material_ui/material_ui.dart';

import '../core/money.dart';
import '../data/models.dart';
import 'receipt_screen.dart';
import 'scope.dart';
import 'theme.dart';

/// Customer return (credit note): the goods come back to the van stock.
class ReturnScreen extends StatefulWidget {
  final String customerId;
  const ReturnScreen({super.key, required this.customerId});
  @override
  State<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends State<ReturnScreen> {
  final qty = <String, int>{}; // item -> thousandths
  String reason = returnReasons.first;
  String invoice = '';
  bool refundCash = false;
  bool saving = false;

  List<SaleLine> lines() {
    final repo = AppScope.repo(context);
    final c = repo.data!.customer(widget.customerId)!;
    return [
      for (final e in qty.entries.where((e) => e.value > 0))
        if (repo.data!.item(e.key) case final it?)
          SaleLine(it.id, it.name, it.uom, e.value, repo.price(c, it.id)?.price ?? 0, it.taxRate),
    ];
  }

  Future<void> pickItem() async {
    final repo = AppScope.repo(context);
    final c = repo.data!.customer(widget.customerId)!;
    final items = repo.data!.items.where((i) => repo.price(c, i.id) != null).toList();
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReturnItemPicker(items: items, priceOf: (i) => repo.price(c, i.id)!.price),
    );
    if (id != null) setState(() => qty[id] = (qty[id] ?? 0) + 1000);
  }

  Future<void> save(Doc draft) async {
    final repo = AppScope.repo(context);
    final c = repo.data!.customer(widget.customerId)!;
    setState(() => saving = true);
    final doc = await repo.saveReturn(c, draft.lines, draft.taxIncluded, refundCash ? draft.totals.total : 0,
        invoiceNumber: invoice, reason: reason);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ReceiptScreen(doc: doc, autoPrint: true)));
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.repo(context);
    final c = repo.data!.customer(widget.customerId)!;
    final ls = lines();
    final taxIncluded = ls.isNotEmpty && (repo.price(c, ls.first.itemId)?.taxIncluded ?? false);
    final draft = Doc(
        id: '', kind: DocKind.ret, number: '', date: DateTime.now(), customerId: c.id, customerName: c.name,
        taxIncluded: taxIncluded, lines: ls);
    final t = draft.totals;
    final invoices = repo.customerInvoices(c);

    return Scaffold(
      appBar: AppBar(title: Text('مرتجع - ${c.name}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: pickItem,
        icon: const Icon(Icons.add),
        label: const Text('إضافة صنف'),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 90), children: [
        for (final l in ls)
          Card(
            child: ListTile(
              title: Text(l.itemName),
              subtitle: Text('${money(l.price)} × ${formatQty(l.qty)} ${l.uom}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => setState(() => qty[l.itemId] = (l.qty - 1000).clamp(0, 1 << 40))),
                Text(formatQty(l.qty), style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                    icon: const Icon(Icons.add_circle_outline), onPressed: () => setState(() => qty[l.itemId] = l.qty + 1000)),
              ]),
            ),
          ),
        if (ls.isEmpty)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('أضف الأصناف المرتجعة من العميل'))),
        if (ls.isNotEmpty) ...[
          Card(
            child: Column(children: [
              ListTile(dense: true, title: const Text('الإجمالي غير شامل الضريبة'), trailing: Text(money(t.net))),
              ListTile(dense: true, title: const Text('ضريبة القيمة المضافة'), trailing: Text(money(t.tax))),
              ListTile(
                title: const Text('إجمالي المرتجع', style: TextStyle(fontWeight: FontWeight.bold)),
                trailing: Text(money(t.total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DropdownButtonFormField<String>(
                  initialValue: reason,
                  decoration: const InputDecoration(labelText: 'سبب الإرجاع'),
                  items: [for (final r in returnReasons) DropdownMenuItem(value: r, child: Text(r))],
                  onChanged: (v) => setState(() => reason = v ?? reason),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: invoice,
                  decoration: const InputDecoration(labelText: 'الفاتورة الأصلية'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('بدون')),
                    for (final i in invoices) DropdownMenuItem(value: i, child: Text(i)),
                  ],
                  onChanged: (v) => setState(() => invoice = v ?? ''),
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('خصم من رصيد العميل')),
                    ButtonSegment(value: true, label: Text('رد المبلغ نقداً')),
                  ],
                  selected: {refundCash},
                  onSelectionChanged: (v) => setState(() => refundCash = v.first),
                ),
                const SizedBox(height: 8),
                Text(
                  refundCash
                      ? 'سيُدفع للعميل ${money(t.total)} من نقدية الموزع'
                      : 'رصيد العميل بعد المرتجع: ${money(repo.debt(c) - t.total)}',
                  style: const TextStyle(color: KaifColors.green, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: saving ? null : () => save(draft),
                  icon: const Icon(Icons.print),
                  label: const Text('حفظ وطباعة إشعار الإرجاع'),
                ),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

class _ReturnItemPicker extends StatefulWidget {
  final List<Item> items;
  final int Function(Item) priceOf;
  const _ReturnItemPicker({required this.items, required this.priceOf});
  @override
  State<_ReturnItemPicker> createState() => _ReturnItemPickerState();
}

class _ReturnItemPickerState extends State<_ReturnItemPicker> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final list = widget.items.where((i) => q.isEmpty || i.name.contains(q) || i.barcode.contains(q)).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'اسم الصنف أو الباركود'),
              onChanged: (v) => setState(() => q = v.trim()),
              onSubmitted: (_) {
                if (list.length == 1) Navigator.pop(context, list.first.id);
              },
            ),
          ),
          Expanded(
            child: ListView(children: [
              for (final i in list)
                ListTile(
                  title: Text(i.name),
                  subtitle: Text(i.uom),
                  trailing: Text(money(widget.priceOf(i))),
                  onTap: () => Navigator.pop(context, i.id),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
