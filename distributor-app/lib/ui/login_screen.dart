import 'package:material_ui/material_ui.dart';

import '../data/api.dart';
import 'home_screen.dart';
import 'scope.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController server, user, password;
  bool busy = false;
  String? error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context).settings;
    server = TextEditingController(text: s.server.isEmpty ? 'https://' : s.server);
    user = TextEditingController(text: s.user);
    password = TextEditingController();
  }

  Future<void> login() async {
    final scope = AppScope.of(context);
    final repo = scope.notifier!;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      repo.api = Api(server.text.trim(), user.text.trim(), password.text);
      await repo.sync();
      if (repo.lastSyncError != null) throw ApiException(repo.lastSyncError!);
      await scope.settings.setLogin(server.text, user.text, password.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 24),
          Center(child: Image.asset('assets/logo.png', width: 140, height: 140)),
          const SizedBox(height: 12),
          Text('تطبيق الموزعين', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          TextField(
            controller: server,
            decoration: const InputDecoration(labelText: 'عنوان الخادم'),
            keyboardType: TextInputType.url,
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(height: 12),
          TextField(controller: user, decoration: const InputDecoration(labelText: 'اسم المستخدم')),
          const SizedBox(height: 12),
          TextField(controller: password, decoration: const InputDecoration(labelText: 'كلمة المرور'), obscureText: true),
          const SizedBox(height: 20),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(error!, style: const TextStyle(color: Color(0xFFB3261E))),
            ),
          FilledButton(
            onPressed: busy ? null : login,
            child: busy ? const CircularProgressIndicator() : const Text('دخول وتحميل البيانات'),
          ),
        ]),
      ),
    );
  }
}
