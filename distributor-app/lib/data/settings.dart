import 'package:shared_preferences/shared_preferences.dart';

/// Connection and printer settings of the device.
class Settings {
  final SharedPreferences prefs;
  Settings(this.prefs);

  static Future<Settings> load() async => Settings(await SharedPreferences.getInstance());

  String get server => prefs.getString('server') ?? '';
  String get user => prefs.getString('user') ?? '';
  String get password => prefs.getString('password') ?? '';
  String get printerMac => prefs.getString('printerMac') ?? '';
  String get printerName => prefs.getString('printerName') ?? '';
  int get paperMm => prefs.getInt('paperMm') ?? 80;

  bool get loggedIn => server.isNotEmpty && user.isNotEmpty;

  Future<void> setLogin(String server, String user, String password) async {
    await prefs.setString('server', server.trim());
    await prefs.setString('user', user.trim());
    await prefs.setString('password', password);
  }

  Future<void> logout() async {
    await prefs.remove('password');
    await prefs.remove('user');
  }

  Future<void> setPrinter(String mac, String name) async {
    await prefs.setString('printerMac', mac);
    await prefs.setString('printerName', name);
  }

  Future<void> setPaper(int mm) => prefs.setInt('paperMm', mm);
}
