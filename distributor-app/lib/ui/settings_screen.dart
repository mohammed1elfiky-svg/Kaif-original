import 'package:material_ui/material_ui.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../printing/printer.dart';
import 'login_screen.dart';
import 'scope.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<BluetoothInfo>? printers;

  Future<void> findPrinters() async {
    if (!await PrinterService.bluetoothEnabled) {
      if (mounted) showMessage(context, 'شغّل البلوتوث واقترن بالطابعة من إعدادات الجوال', error: true);
      return;
    }
    final list = await PrinterService.paired();
    setState(() => printers = list);
  }

  Future<void> logout() async {
    final scope = AppScope.of(context);
    final repo = scope.notifier!;
    if (repo.pendingCount > 0) {
      showMessage(context, 'توجد مستندات لم تُرسل. قم بالمزامنة قبل تسجيل الخروج.', error: true);
      return;
    }
    await scope.settings.logout();
    await repo.clearData();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final s = scope.settings;
    final repo = scope.notifier!;
    return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
      Card(
        child: Column(children: [
          ListTile(title: const Text('الموزع'), subtitle: Text(repo.data?.distributor.name ?? '')),
          ListTile(title: const Text('السيارة'), subtitle: Text(repo.data?.distributor.location ?? '')),
          ListTile(title: const Text('الخادم'), subtitle: Text(s.server, textDirection: TextDirection.ltr)),
        ]),
      ),
      Card(
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.print),
            title: const Text('الطابعة'),
            subtitle: Text(s.printerName.isEmpty ? 'لم يتم الاختيار' : s.printerName),
            trailing: TextButton(onPressed: findPrinters, child: const Text('بحث')),
          ),
          for (final p in printers ?? <BluetoothInfo>[])
            ListTile(
              title: Text(p.name),
              subtitle: Text(p.macAdress, textDirection: TextDirection.ltr),
              trailing: p.macAdress == s.printerMac ? const Icon(Icons.check) : null,
              onTap: () async {
                await s.setPrinter(p.macAdress, p.name);
                setState(() {});
              },
            ),
          if (printers != null && printers!.isEmpty)
            const ListTile(title: Text('لا توجد طابعات مقترنة. اقترن بالطابعة من إعدادات البلوتوث في الجوال.')),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 80, label: Text('ورق 80 مم')),
                ButtonSegment(value: 58, label: Text('ورق 58 مم')),
              ],
              selected: {s.paperMm},
              onSelectionChanged: (v) async {
                await s.setPaper(v.first);
                setState(() {});
              },
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: OutlinedButton.icon(onPressed: logout, icon: const Icon(Icons.logout), label: const Text('تسجيل الخروج')),
      ),
    ]);
  }
}
