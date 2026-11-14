import 'package:material_ui/material_ui.dart';

import '../data/repository.dart';
import '../data/settings.dart';

/// Gives the screens access to the repository and the settings, and rebuilds them when the data changes.
class AppScope extends InheritedNotifier<Repository> {
  final Settings settings;
  const AppScope({super.key, required Repository repo, required this.settings, required super.child})
      : super(notifier: repo);

  static AppScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!;
  static Repository repo(BuildContext context) => of(context).notifier!;
}

void showMessage(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: error ? const Color(0xFFB3261E) : null,
  ));
}
