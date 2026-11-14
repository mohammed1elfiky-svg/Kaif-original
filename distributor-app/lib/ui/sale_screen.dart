import 'package:material_ui/material_ui.dart';

import '../core/money.dart';
import '../data/models.dart';
import 'receipt_screen.dart';
import 'scope.dart';
import 'theme.dart';

class SaleScreen extends StatefulWidget {
  final String customerId;
  const SaleScreen({super.key, required this.customerId});
  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  final qty = <String, int>{}; // item -> thousandths
  final paidCtrl = TextEditingController();
  PayMethod method = PayMethod.cash;
  bool paidEdited = false;
  bool saving = false;

  List<SaleLine> lines(BuildContext context) {
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
    final items = repo.data!.items.where((i) => repo.stock(i.id) > 0 && repo.price(c, i.id) != null).toList();
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ItemPicker(items: items, priceOf: (i) => repo.price(c, i.id)!.price, stockOf: repo.stock),
    );
    if (id != null) setState(() => qty[id] = (qty[id] ?? 0) + 1000);
  }

  void setQty(String id, int v) {
    final max = AppScope.repo(context).stock(id);
    setState(() => qty[id] = v.clamp(0, max));
  }

  Future<void> save(Doc draft) async {
    final repo = AppScope.repo(context);
    final c = repo.data!.customer(widget.customerId)!;
    final paid = paidEdited ? toHalalas(paidCtrl.text) : draft.totals.total;
    if (paid < 0 || paid > draft.totals.total) {
      showMessage(context, 'المبلغ المدفوع غير صحيح', error: true);
      return;
    }
    final check = repo.checkSale(c, draft.totals.total, paid);
    if (!check.ok) {
      showMessage(context, check.error!, error: true);
      return;
    }
    setState(() => saving = true);
    final doc = await repo.saveInvoice(c, draft.lines, draft.taxIncluded, paid, method);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ReceiptScreen(doc: doc, autoPrint: true)));
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.repo(context);
    final c = repo.data!.customer(widget.customerId)!;
    final ls = lines(context);
    final taxIncluded = ls.isNotEmpty && (repo.price(c, ls.first.itemId)?.taxIncluded ?? false);
    final draft = Doc(
        id: '', kind: DocKind.invoice, number: '', date: DateTime.now(), customerId: c.id, customerName: c.name,
        taxIncluded: taxIncluded, lines: ls);
    final t = draft.totals;
    if (!paidEdited) paidCtrl.text = formatMoney(t.total, grouping: false);
    final paid = paidEdited ? toHalalas(paidCtrl.text) : t.total;
    final check = repo.checkSale(c, t.total, paid);

    return Scaffold(
      appBar: AppBar(title: Text('بيع - ${c.name}')),
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
              subtitle: Text('${money(l.price)} × ${formatQty(l.qty)} ${l.uom}  ·  المتوفر ${formatQty(repo.stock(l.itemId))}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => setQty(l.itemId, l.qty - 1000)),
                Text(formatQty(l.qty), style: Theme.of(context).textTheme.titleMedium),
                IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => setQty(l.itemId, l.qty + 1000)),
              ]),
            ),
          ),
        if (ls.isEmpty)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('أضف أصنافاً من مخزون السيارة'))),
        if (ls.isNotEmpty) ...[
          Card(
            child: Column(children: [
              ListTile(dense: true, title: const Text('الإجمالي غير شامل الضريبة'), trailing: Text(money(t.net))),
              ListTile(dense: true, title: const Text('ضريبة القيمة المضافة'), trailing: Text(money(t.tax))),
              ListTile(
                title: const Text('الإجمالي شامل الضريبة', style: TextStyle(fontWeight: FontWeight.bold)),
                trailing: Text(money(t.total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SegmentedButton<PayMethod>(
                  segments: const [
                    ButtonSegment(value: PayMethod.cash, label: Text('نقداً'), icon: Icon(Icons.money)),
                    ButtonSegment(value: PayMethod.bank, label: Text('تحويل / بطاقة'), icon: Icon(Icons.credit_card)),
                  ],
                  selected: {method},
                  onSelectionChanged: (s) => setState(() => method = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: paidCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'المبلغ المدفوع الآن (0 = آجل بالكامل)'),
                  onChanged: (_) => setState(() => paidEdited = true),
                ),
                const SizedBox(height: 8),
                if (paid < t.total) Text('الآجل: ${money(t.total - paid)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                if (!check.ok) Text(check.error!, style: const TextStyle(color: KaifColors.danger)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: saving || !check.ok ? null : () => save(draft),
                  icon: const Icon(Icons.print),
                  label: const Text('حفظ وطباعة الفاتورة'),
                ),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

class _ItemPicker extends StatefulWidget {
  final List<Item> items;
  final int Function(Item) priceOf;
  final int Function(String) stockOf;
  const _ItemPicker({required this.items, required this.priceOf, required this.stockOf});
  @override
  State<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends State<_ItemPicker> {
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
                  subtitle: Text('المتوفر: ${formatQty(widget.stockOf(i.id))} ${i.uom}'),
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
