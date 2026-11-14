import 'package:material_ui/material_ui.dart';

import 'data/api.dart';
import 'data/db.dart';
import 'data/location.dart';
import 'data/repository.dart';
import 'data/settings.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';
import 'ui/scope.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  final repo = Repository(await LocalDb.open())..locate = currentLocation;
  await repo.load();
  if (settings.loggedIn) repo.api = Api(settings.server, settings.user, settings.password);
  runApp(KaifDistributorApp(repo: repo, settings: settings));
}

class KaifDistributorApp extends StatelessWidget {
  final Repository repo;
  final Settings settings;
  const KaifDistributorApp({super.key, required this.repo, required this.settings});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      repo: repo,
      settings: settings,
      child: MaterialApp(
        title: 'الكيف الأصلي - الموزع',
        debugShowCheckedModeBanner: false,
        theme: kaifTheme(),
        locale: const Locale('ar', 'SA'),
        supportedLocales: const [Locale('ar', 'SA')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: settings.loggedIn && repo.hasData ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }
}
