import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../printing/printer.dart';
import '../printing/receipt.dart';
import 'scope.dart';

/// Preview of the document as it is printed, with printing to the Bluetooth printer.
class ReceiptScreen extends StatefulWidget {
  final Doc doc;
  final bool autoPrint;
  const ReceiptScreen({super.key, required this.doc, this.autoPrint = false});
  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final boundary = GlobalKey();
  bool printing = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoPrint) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (AppScope.of(context).settings.printerMac.isNotEmpty) print();
      });
    }
  }

  Future<void> print() async {
    final s = AppScope.of(context).settings;
    if (s.printerMac.isEmpty) {
      showMessage(context, 'اختر الطابعة من الإعدادات أولاً', error: true);
      return;
    }
    setState(() => printing = true);
    try {
      await PrinterService.printBoundary(boundary, mac: s.printerMac, paperMm: s.paperMm);
      if (mounted) showMessage(context, 'تمت الطباعة');
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final company = scope.notifier!.data!.company;
    return Scaffold(
      appBar: AppBar(title: Text(widget.doc.number)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Material(
            elevation: 2,
            child: RepaintBoundary(
              key: boundary,
              child: Receipt(doc: widget.doc, company: company, paperMm: scope.settings.paperMm),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: printing ? null : print,
            icon: printing ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator()) : const Icon(Icons.print),
            label: const Text('طباعة'),
          ),
        ),
      ),
    );
  }
}
