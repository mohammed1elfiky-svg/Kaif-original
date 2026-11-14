import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../core/money.dart';
import '../data/models.dart';
import 'closing_screen.dart';
import 'customer_screen.dart';
import 'receipt_screen.dart';
import 'scope.dart';
import 'settings_screen.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;

  Future<void> sync() async {
    final repo = AppScope.repo(context);
    await repo.sync();
    if (!mounted) return;
    final errors = repo.docs.where((d) => d.status == DocStatus.error).length;
    if (repo.lastSyncError != null) {
      showMessage(context, 'لم تتم المزامنة، ستُرسل المستندات لاحقاً: ${repo.lastSyncError}', error: true);
    } else if (errors > 0) {
      showMessage(context, 'تمت المزامنة، لكن $errors مستند رفضه الخادم. راجع المستندات.', error: true);
    } else {
      showMessage(context, 'تمت المزامنة');
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.repo(context);
    final pending = repo.pendingCount;
    final pages = [const _CustomersTab(), const _StockTab(), const _DocsTab(), const SettingsScreen()];
    return Scaffold(
      appBar: AppBar(
        title: Text(repo.data?.distributor.name ?? 'الموزع'),
        actions: [
          IconButton(
            tooltip: 'إقفال اليوم',
            icon: const Icon(Icons.lock_clock),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ClosingScreen())),
          ),
          if (repo.syncing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            )
          else
            IconButton(
              tooltip: 'مزامنة',
              onPressed: sync,
              icon: Badge(
                isLabelVisible: pending > 0,
                label: Text('$pending'),
                child: const Icon(Icons.sync),
              ),
            ),
        ],
      ),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.storefront), label: 'العملاء'),
          NavigationDestination(icon: Icon(Icons.inventory_2), label: 'المخزون'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'المستندات'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'الإعدادات'),
        ],
      ),
    );
  }
}

class _CustomersTab extends StatefulWidget {
  const _CustomersTab();
  @override
  State<_CustomersTab> createState() => _CustomersTabState();
}

class _CustomersTabState extends State<_CustomersTab> {
  String query = '';
  bool routeOnly = true;

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.repo(context);
    final route = repo.todayRoute();
    final showRoute = routeOnly && route.isNotEmpty && query.isEmpty;
    final customers = showRoute
        ? route
        : ((repo.data?.customers ?? [])
            .where((c) => query.isEmpty || c.name.contains(query) || c.phone.contains(query) || c.id.contains(query))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name)));
    final visited = route.where(repo.visitedToday).length;
    return Column(children: [
      if (route.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text('خط سير اليوم ($visited/${route.length})')),
              const ButtonSegment(value: false, label: Text('كل العملاء')),
            ],
            selected: {routeOnly},
            onSelectionChanged: (v) => setState(() => routeOnly = v.first),
          ),
        ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث بالاسم أو الهاتف'),
          onChanged: (v) => setState(() => query = v.trim()),
        ),
      ),
      if (repo.downloadedAt != null)
        Text('آخر تحديث: ${DateFormat('yyyy-MM-dd HH:mm').format(repo.downloadedAt!)}',
            style: Theme.of(context).textTheme.bodySmall),
      Expanded(
        child: ListView.builder(
          itemCount: customers.length,
          itemBuilder: (_, i) {
            final c = customers[i];
            final debt = repo.debt(c);
            final available = repo.availableCredit(c);
            final overdue = c.maxOverdueDays != null && c.overdueDays > c.maxOverdueDays!;
            return Card(
              child: ListTile(
                title: Text(c.name),
                subtitle: Text([
                  'الرصيد: ${money(debt)}',
                  if (available != null) 'المتاح: ${money(available)}',
                  if (overdue) 'متأخر ${c.overdueDays} يوم',
                ].join('  ·  ')),
                leading: showRoute
                    ? Icon(repo.visitedToday(c) ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: repo.visitedToday(c) ? KaifColors.leaf : null)
                    : null,
                trailing: overdue ? const Icon(Icons.warning_amber, color: KaifColors.danger) : const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CustomerScreen(customerId: c.id))),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _StockTab extends StatelessWidget {
  const _StockTab();
  @override
  Widget build(BuildContext context) {
    final repo = AppScope.repo(context);
    final items = repo.data?.items ?? [];
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text('مخزون السيارة: ${repo.data?.distributor.location ?? ''}', style: Theme.of(context).textTheme.titleMedium),
      ),
      for (final it in items)
        Card(
          child: ListTile(
            title: Text(it.name),
            subtitle: Text(it.barcode),
            trailing: Text('${formatQty(repo.stock(it.id))} ${it.uom}', style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
    ]);
  }
}

class _DocsTab extends StatelessWidget {
  const _DocsTab();
  @override
  Widget build(BuildContext context) {
    final repo = AppScope.repo(context);
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    return ListView(children: [
      for (final d in repo.printableDocs)
        Card(
          child: ListTile(
            leading: Icon(
              d.status == DocStatus.sent
                  ? Icons.cloud_done
                  : d.status == DocStatus.error
                      ? Icons.error_outline
                      : Icons.cloud_upload_outlined,
              color: d.status == DocStatus.error ? KaifColors.danger : KaifColors.green,
            ),
            title: Text('${docTitle(d.kind)} ${d.number} - ${d.customerName}'),
            subtitle: Text(d.status == DocStatus.error
                ? 'رفضه الخادم: ${d.error}'
                : '${fmt.format(d.date.toLocal())}  ·  ${d.status == DocStatus.sent ? 'مُرسل' : 'بانتظار المزامنة'}'),
            trailing: Text(money(switch (d.kind) {
              DocKind.invoice || DocKind.ret => d.totals.total,
              DocKind.closing => d.summary['cashHanded'] ?? 0,
              _ => d.paid,
            })),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReceiptScreen(doc: d))),
          ),
        ),
    ]);
  }
}

String docTitle(DocKind k) => switch (k) {
      DocKind.invoice => 'فاتورة',
      DocKind.payment => 'سند قبض',
      DocKind.ret => 'مرتجع',
      DocKind.closing => 'إقفال يوم',
      DocKind.visit => 'زيارة',
    };
